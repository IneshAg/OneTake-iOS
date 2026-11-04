#!/usr/bin/env python3
"""
Headshot Pose Classifier & Yaw Regressor Training Pipeline
===========================================================
Trains a real-time mobile neural network on front, left profile, and right profile
headshots with continuous yaw regression.
Exports the trained model to Apple CoreML (.mlpackage) for real-time on-device
inference in OneTake's CameraController and ProfileViews.
"""

import os
import sys
import json
import math
import random
import shutil
from pathlib import Path

import torch
import torch.nn as nn
import torch.optim as optim
from torch.utils.data import Dataset, DataLoader
import torchvision.transforms as T
import torchvision.models as models
from PIL import Image

try:
    import coremltools as ct
except ImportError:
    ct = None
    print("[Warning] coremltools not available; CoreML export will be skipped.")

BASE_DIR = Path(__file__).resolve().parent.parent
DATASET_DIR = BASE_DIR / "dataset"
HEADSHOTS_DIR = DATASET_DIR / "headshots"
OUTPUT_MODEL_DIR = BASE_DIR / "OneTake" / "Models"

CLASS_NAMES = ["front", "left_profile", "right_profile"]
CLASS_TO_IDX = {name: i for i, name in enumerate(CLASS_NAMES)}
IDX_TO_CLASS = {i: name for i, name in enumerate(CLASS_NAMES)}

# Standard target yaw radians for each class
CLASS_YAW_RAD = {
    "front": 0.0,
    "left_profile": 1.45,    # ~ +83°
    "right_profile": -1.45   # ~ -83°
}

# -------------------------------------------------------------------------
# 1. Dataset & Data Augmentation
# -------------------------------------------------------------------------

class HeadshotPoseDataset(Dataset):
    """
    Dataset loader for headshots with pose classification labels and continuous yaw angles.
    Includes data augmentation: random crops, color jitter, affine rotation,
    and horizontal flip with label inversion (left <-> right, yaw * -1).
    """
    def __init__(self, samples, is_training=True):
        self.samples = samples
        self.is_training = is_training

        # Standard ImageNet normalization
        self.norm = T.Normalize(mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225])

        self.color_jitter = T.ColorJitter(brightness=0.3, contrast=0.3, saturation=0.25)
        self.affine = T.RandomAffine(degrees=8, translate=(0.04, 0.04), scale=(0.96, 1.04))

    def __len__(self):
        # In training, expand dataset with virtual augmented instances
        return len(self.samples) * (12 if self.is_training else 1)

    def __getitem__(self, idx):
        sample_idx = idx % len(self.samples)
        sample = self.samples[sample_idx]

        img = Image.open(sample["path"]).convert("RGB")
        cls_idx = sample["class_idx"]
        yaw = sample["yaw_radians"]

        if self.is_training:
            # 1. Horizontal Flip with yaw/class inversion
            if random.random() > 0.5:
                img = img.transpose(Image.FLIP_LEFT_RIGHT)
                if cls_idx == 1:  # left_profile -> right_profile
                    cls_idx = 2
                    yaw = -yaw
                elif cls_idx == 2:  # right_profile -> left_profile
                    cls_idx = 1
                    yaw = -yaw
                else:
                    yaw = -yaw

            # 2. Color and Lighting variation
            img = self.color_jitter(img)

        # Resize to standard network input 224x224
        img = img.resize((224, 224), Image.Resampling.BILINEAR)

        tensor = T.functional.to_tensor(img)

        if self.is_training:
            tensor = self.affine(tensor)

        tensor = self.norm(tensor)

        return (
            tensor,
            torch.tensor(cls_idx, dtype=torch.long),
            torch.tensor(yaw, dtype=torch.float32)
        )

def load_headshot_corpus():
    """Discovers all available headshot samples and annotations."""
    samples = []
    for angle_key in CLASS_NAMES:
        folder = HEADSHOTS_DIR / angle_key
        if not folder.exists():
            continue
        for img_path in folder.glob("*.jpg"):
            meta_path = folder / f"{img_path.name}.json"
            if not meta_path.exists():
                meta_path = folder / f"{img_path.stem}.json"

            yaw = CLASS_YAW_RAD[angle_key]
            if meta_path.exists():
                try:
                    with open(meta_path) as f:
                        meta = json.load(f)
                        yaw = float(meta.get("yaw_radians", yaw))
                except Exception:
                    pass

            samples.append({
                "path": img_path,
                "class_name": angle_key,
                "class_idx": CLASS_TO_IDX[angle_key],
                "yaw_radians": yaw
            })

    print(f"[Dataset] Discovered {len(samples)} base headshot samples across classes: "
          f"{ {k: sum(1 for s in samples if s['class_name'] == k) for k in CLASS_NAMES} }")
    return samples

# -------------------------------------------------------------------------
# 2. Neural Network Architecture (HeadshotPoseNet)
# -------------------------------------------------------------------------

class HeadshotPoseNet(nn.Module):
    """
    Lightweight, high-speed multi-task CNN for iOS deployment.
    Backbone: MobileNetV3-Small (pretrained).
    Heads:
      1. pose_logits: 3-class classification (front, left_profile, right_profile)
      2. yaw_angle: continuous yaw regression in radians
    """
    def __init__(self, pretrained=True):
        super().__init__()
        weights = models.MobileNet_V3_Small_Weights.DEFAULT if pretrained else None
        backbone = models.mobilenet_v3_small(weights=weights)

        # Feature extractor
        self.features = backbone.features
        self.avgpool = backbone.avgpool

        feat_dim = backbone.classifier[0].in_features  # 576

        # Shared feature projection
        self.shared_fc = nn.Sequential(
            nn.Linear(feat_dim, 256),
            nn.Hardswish(),
            nn.Dropout(p=0.2)
        )

        # Classification Head (3 classes)
        self.fc_class = nn.Linear(256, 3)

        # Yaw Regression Head (1 continuous value)
        self.fc_yaw = nn.Sequential(
            nn.Linear(256, 64),
            nn.Hardswish(),
            nn.Linear(64, 1)
        )

    def forward(self, x):
        feat = self.features(x)
        feat = self.avgpool(feat)
        feat = torch.flatten(feat, 1)
        shared = self.shared_fc(feat)

        pose_logits = self.fc_class(shared)
        yaw = self.fc_yaw(shared).squeeze(-1)

        return pose_logits, yaw

# -------------------------------------------------------------------------
# 3. Model Training & Evaluation Routine
# -------------------------------------------------------------------------

def train_model(epochs=15, batch_size=16, lr=1e-3):
    print("\n=======================================================")
    print(" Training HeadshotPoseNet Model")
    print("=======================================================")

    samples = load_headshot_corpus()
    if not samples:
        print("[Error] No headshots found. Run scrape_audition_data.py first.")
        return None

    # Deterministic split: 80% train, 20% validation
    random.seed(42)
    random.shuffle(samples)
    split_idx = max(1, int(len(samples) * 0.8))
    train_samples = samples[:split_idx]
    val_samples = samples[split_idx:]

    train_ds = HeadshotPoseDataset(train_samples, is_training=True)
    val_ds = HeadshotPoseDataset(val_samples, is_training=False)

    train_loader = DataLoader(train_ds, batch_size=batch_size, shuffle=True, drop_last=True)
    val_loader = DataLoader(val_ds, batch_size=batch_size, shuffle=False)

    device = torch.device("mps" if torch.backends.mps.is_available() else "cpu")
    print(f"[Device] Training on: {device}")

    model = HeadshotPoseNet(pretrained=True).to(device)

    ce_loss_fn = nn.CrossEntropyLoss()
    mse_loss_fn = nn.MSELoss()

    optimizer = optim.AdamW(model.parameters(), lr=lr, weight_decay=1e-4)
    scheduler = optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max=epochs)

    for epoch in range(1, epochs + 1):
        model.train()
        total_loss = 0.0
        correct_cls = 0
        total_count = 0

        for images, labels, yaws in train_loader:
            images = images.to(device)
            labels = labels.to(device)
            yaws = yaws.to(device)

            optimizer.zero_grad()
            logits, pred_yaw = model(images)

            loss_cls = ce_loss_fn(logits, labels)
            loss_yaw = mse_loss_fn(pred_yaw, yaws)
            loss = loss_cls + 2.5 * loss_yaw

            loss.backward()
            optimizer.step()

            total_loss += loss.item() * images.size(0)
            preds = logits.argmax(dim=-1)
            correct_cls += (preds == labels).sum().item()
            total_count += images.size(0)

        scheduler.step()

        train_acc = (correct_cls / total_count) * 100.0
        avg_loss = total_loss / total_count

        # Validation step
        model.eval()
        val_correct = 0
        val_yaw_err_deg = 0.0
        val_count = 0
        with torch.no_grad():
            for images, labels, yaws in val_loader:
                images = images.to(device)
                labels = labels.to(device)
                yaws = yaws.to(device)

                logits, pred_yaw = model(images)
                preds = logits.argmax(dim=-1)
                val_correct += (preds == labels).sum().item()

                # Yaw error in degrees
                err_rad = torch.abs(pred_yaw - yaws)
                val_yaw_err_deg += (err_rad * (180.0 / math.pi)).sum().item()
                val_count += images.size(0)

        val_acc = (val_correct / val_count) * 100.0 if val_count else 0
        val_mae = (val_yaw_err_deg / val_count) if val_count else 0

        print(f"Epoch [{epoch:02d}/{epochs:02d}] - Loss: {avg_loss:.4f} | "
              f"Train Acc: {train_acc:.1f}% | Val Acc: {val_acc:.1f}% | Val Yaw MAE: {val_mae:.1f}°")

    print("\n Training Complete!")
    return model

# -------------------------------------------------------------------------
# 4. CoreML Export (.mlpackage)
# -------------------------------------------------------------------------

class CoreMLWrapper(nn.Module):
    """
    Inference-ready wrapper that exposes softmax probabilities and continuous yaw
    with pre-applied ImageNet normalization.
    """
    def __init__(self, net):
        super().__init__()
        self.net = net
        self.softmax = nn.Softmax(dim=-1)

    def forward(self, x):
        # x is [1, 3, 224, 224] in [0, 1]
        mean = torch.tensor([0.485, 0.456, 0.406]).view(1, 3, 1, 1).to(x.device)
        std = torch.tensor([0.229, 0.224, 0.225]).view(1, 3, 1, 1).to(x.device)
        norm_x = (x - mean) / std

        logits, yaw = self.net(norm_x)
        probs = self.softmax(logits)
        yaw_deg = yaw * (180.0 / math.pi)

        return probs, yaw, yaw_deg

def export_to_coreml(model, output_dir=OUTPUT_MODEL_DIR):
    """Converts PyTorch model to Apple CoreML (.mlmodel) and compiles with coremlc for iOS deployment."""
    if ct is None:
        print("[Skip] coremltools not available.")
        return

    import subprocess

    print("\n=======================================================")
    print(" Exporting to Apple CoreML (.mlmodel)")
    print("=======================================================")

    output_dir.mkdir(parents=True, exist_ok=True)
    mlmodel_path = output_dir / "HeadshotPoseClassifier.mlmodel"

    model.eval()
    model.cpu()
    wrapper = CoreMLWrapper(model)
    wrapper.eval()

    example_input = torch.rand(1, 3, 224, 224)
    traced_model = torch.jit.trace(wrapper, example_input)

    image_input = ct.ImageType(
        name="image",
        shape=(1, 3, 224, 224),
        scale=1.0 / 255.0,  # transforms uint8 [0, 255] to [0.0, 1.0]
        color_layout=ct.colorlayout.RGB
    )

    coreml_model = ct.convert(
        traced_model,
        inputs=[image_input],
        convert_to="neuralnetwork",
        outputs=[
            ct.TensorType(name="pose_probabilities"),
            ct.TensorType(name="predicted_yaw_radians"),
            ct.TensorType(name="predicted_yaw_degrees")
        ]
    )

    # Set metadata
    coreml_model.author = "Inesh Agarwal <ineshag123@gmail.com>"
    coreml_model.license = "Proprietary / OneTake iOS"
    coreml_model.short_description = (
        "Headshot 3-Pose Angle Classifier and Continuous Yaw Regressor for OneTake. "
        "Detects Front (0°), Left Profile (+90°), and Right Profile (-90°) poses."
    )
    coreml_model.input_description["image"] = "Portrait camera frame (224x224 RGB)"
    coreml_model.output_description["pose_probabilities"] = "Probabilities for [front, left_profile, right_profile]"
    coreml_model.output_description["predicted_yaw_radians"] = "Head yaw in radians (matching VNFaceObservation.yaw)"
    coreml_model.output_description["predicted_yaw_degrees"] = "Head yaw in degrees (-90° to +90°)"

    coreml_model.save(str(mlmodel_path))
    print(f" Successfully exported CoreML model: {mlmodel_path}")

    # Compile with Apple xcrun coremlc
    try:
        env = os.environ.copy()
        env["DEVELOPER_DIR"] = "/Applications/Xcode.app/Contents/Developer"
        cmd = ["xcrun", "coremlc", "compile", str(mlmodel_path), str(output_dir)]
        subprocess.run(cmd, env=env, check=True)
        print(f" Successfully compiled with coremlc: {output_dir / 'HeadshotPoseClassifier.mlmodelc'}")
    except Exception as e:
        print(f" [Warning] coremlc compilation note: {e}")

    # Also save a PyTorch checkpoint for future fine-tuning
    pt_checkpoint = output_dir / "headshot_pose_net.pth"
    torch.save(model.state_dict(), pt_checkpoint)
    print(f" Saved PyTorch weights checkpoint: {pt_checkpoint}")

def main():
    trained_net = train_model(epochs=12, batch_size=8, lr=7e-4)
    if trained_net is not None:
        export_to_coreml(trained_net)

if __name__ == "__main__":
    main()
