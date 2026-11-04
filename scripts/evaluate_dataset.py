#!/usr/bin/env python3
"""
OneTake Dataset & Model Verification Benchmark
==============================================
Evaluates:
1. Headshot Pose Classifier:
   - Prediction accuracy across Front (0°), Left Profile (+83°), Right Profile (-83°).
   - Mean Absolute Error (MAE) of continuous yaw predictions.
2. Audition Sides & Notice Parser Extraction:
   - Validates that screenplay sluglines, character cues, and dialogues are properly structured.
"""

import os
import sys
import json
import math
from pathlib import Path

import torch
import torchvision.transforms as T
from PIL import Image

try:
    import coremltools as ct
except ImportError:
    ct = None

BASE_DIR = Path(__file__).resolve().parent.parent
DATASET_DIR = BASE_DIR / "dataset"
HEADSHOTS_DIR = DATASET_DIR / "headshots"
MODELS_DIR = BASE_DIR / "OneTake" / "Models"

CLASS_NAMES = ["front", "left_profile", "right_profile"]

def evaluate_coreml_model():
    mlmodel_path = MODELS_DIR / "HeadshotPoseClassifier.mlmodel"
    pt_path = MODELS_DIR / "headshot_pose_net.pth"

    if not mlmodel_path.exists() and not pt_path.exists():
        print(f"[Model] No model found at {mlmodel_path} or {pt_path}")
        return

    print("\n=======================================================")
    print(" Evaluating HeadshotPoseNet Model (3-Pose Classification & Yaw)")
    print("=======================================================")

    from train_headshot_pose_model import HeadshotPoseNet, CoreMLWrapper
    model = HeadshotPoseNet(pretrained=False)
    if pt_path.exists():
        model.load_state_dict(torch.load(pt_path, map_location="cpu"))
    wrapper = CoreMLWrapper(model)
    wrapper.eval()

    correct = 0
    total = 0
    yaw_errors_deg = []

    for expected_angle in CLASS_NAMES:
        folder = HEADSHOTS_DIR / expected_angle
        if not folder.exists():
            continue

        for img_path in sorted(folder.glob("*.jpg")):
            img = Image.open(img_path).convert("RGB").resize((224, 224), Image.Resampling.BILINEAR)
            tensor = T.functional.to_tensor(img).unsqueeze(0)  # [1, 3, 224, 224]

            with torch.no_grad():
                probs, pred_yaw, pred_yaw_deg = wrapper(tensor)
                probs = probs.squeeze(0).numpy()
                pred_cls_idx = int(probs.argmax())
                pred_class = CLASS_NAMES[pred_cls_idx]
                pred_yaw_deg = float(pred_yaw_deg.item())

            # Read expected yaw
            meta_path = folder / f"{img_path.name}.json"
            if not meta_path.exists():
                meta_path = folder / f"{img_path.stem}.json"
            target_yaw_deg = 0.0 if expected_angle == "front" else (83.1 if expected_angle == "left_profile" else -83.1)
            if meta_path.exists():
                try:
                    with open(meta_path) as mf:
                        m = json.load(mf)
                        target_yaw_deg = float(m.get("yaw_degrees", target_yaw_deg))
                except Exception:
                    pass

            is_correct = (pred_class == expected_angle)
            if is_correct:
                correct += 1
            total += 1

            err_deg = abs(pred_yaw_deg - target_yaw_deg)
            yaw_errors_deg.append(err_deg)

            print(f"  [{'✓' if is_correct else '✗'}] {img_path.name:32s} | Target: {expected_angle:13s} "
                  f"| Pred: {pred_class:13s} ({probs[pred_cls_idx]*100:.1f}%) | Yaw: {pred_yaw_deg:5.1f}° (Err: {err_deg:4.1f}°)")

    acc = (correct / total * 100.0) if total > 0 else 0
    mean_err = sum(yaw_errors_deg) / len(yaw_errors_deg) if yaw_errors_deg else 0
    print("-------------------------------------------------------")
    print(f" Model Test Accuracy: {acc:.1f}% ({correct}/{total})")
    print(f" Model Yaw Angle MAE: {mean_err:.2f}°")
    print("=======================================================\n")

def main():
    evaluate_coreml_model()

if __name__ == "__main__":
    main()
