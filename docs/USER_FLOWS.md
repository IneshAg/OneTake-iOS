# OneTake iOS — User Flows

This document details the primary user journeys through OneTake iOS, accompanied by visual Mermaid flowcharts.

---

## 1. End-to-End Audition Workflow

The complete journey from casting notice ingestion to final submission.

```mermaid
flowchart TD
    Start([Receive Audition]) --> Import[Add Audition & Import Notice/Sides]
    Import --> Extract[Vision OCR & Document Parsing]
    Extract --> ReviewDetails[Confirm Project & Role Details]
    ReviewDetails --> Overview[Project Overview & Checklist]
    
    Overview --> StepHeadshot[Headshot Capture / Selection]
    StepHeadshot --> StepSlate[Record Slate]
    
    StepSlate --> ReqFullLength{Full Length Requested?}
    ReqFullLength -- Yes --> StepFullLength[Record Full Length Video]
    ReqFullLength -- No --> StepScenePrep[Scene Preparation & Reader Recording]
    StepFullLength --> StepScenePrep
    
    StepScenePrep --> ModeChoice{Mode Choice}
    ModeChoice -- Rehearse --> RunLines[Run Lines / Practice Drills]
    RunLines --> ShootMode
    ModeChoice -- Film --> ShootMode[Shoot Scene Takes]
    
    ShootMode --> ReviewTakes[Review & Circle Send Take]
    ReviewTakes --> MoreScenes{More Scenes?}
    MoreScenes -- Yes --> StepScenePrep
    MoreScenes -- No --> TapeCheck[Tape Check Technical Analysis]
    
    TapeCheck --> Package[Package Audition]
    Package --> DeliveryChoice{Delivery Choice}
    DeliveryChoice -- Hosted Link --> ShareLink[Publish iCloud Share Link]
    DeliveryChoice -- Local Archive --> SeparateElements[Export Separate Elements .ZIP]
    
    ShareLink --> SentScreen[Sent Confirmation & Reminders]
    SeparateElements --> SentScreen
    SentScreen --> Done([Audition Completed])
```

---

## 2. Document Import Workflow (`WORKFLOW-PDF-01`)

Casting calls and script sides must remain strictly independent documents. Importing one must never overwrite or destroy the other.

```mermaid
flowchart TD
    AddAction([Tap + Add Audition]) --> DocSource{Select Source}
    DocSource --> Picker[Document Picker PDF]
    DocSource --> Camera[VisionKit Scan Pages]
    DocSource --> Paste[Paste Clipboard Text]
    DocSource --> ShareExt[iOS Share Extension]

    DocSource --> AssignDoc{Assign Document Type}
    
    AssignDoc -- Casting Call PDF --> NoticeParse[NoticeParser.extractNotice]
    NoticeParse --> SetNotice[Populate Project, Role, Deadline, Instructions]
    SetNotice --> PreserveSides[Preserve Existing Script Sides Intact]

    AssignDoc -- Script Sides PDF --> ScriptParse[ScriptParser.parse]
    ScriptParse --> SplitScenes[Chunk Scenes at Sluglines / SCENE N]
    SplitScenes --> SetScenes[Populate Scene Pieces & Dialogue Cues]
    SetScenes --> PreserveNotice[Preserve Existing Notice Details Intact]

    PreserveSides --> DraftReady[Audition Draft Ready]
    PreserveNotice --> DraftReady
    DraftReady --> Confirm([Save Audition to Store])
```

---

## 3. Practice & Rehearsal Workflow

Standalone line-learning drills operate independently of audition recording state.

```mermaid
flowchart TD
    PracticeTab([Open Practice Tab]) --> ChooseDrill{Choose Practice Mode}
    
    ChooseDrill --> FullLines[Prepare: Full Lines / Hide Mine]
    ChooseDrill --> RunLines[Run Lines with Voice Recognition]
    ChooseDrill --> FirstLetter[First-Letter Prompt Drill]
    ChooseDrill --> MaskReveal[Mask & Reveal 25% - 100%]
    ChooseDrill --> AudioWalk[Audio Walk Loop]

    RunLines --> RecReader[Record Partner Cues Line-by-Line]
    RecReader --> StartRehearsal[Start Voice-Prompted Rehearsal]
    StartRehearsal --> SpeakLine[Actor Speaks Dialogue]
    SpeakLine --> SpeechRecog{Speech Recognized?}
    SpeechRecog -- Yes --> PlayReader[Play Recorded Reader Cue]
    SpeechRecog -- Need Help --> LinePrompt[Actor says 'Line?' -> Shows Prompt]
    LinePrompt --> SpeakLine
    PlayReader --> NextLine{More Lines?}
    NextLine -- Yes --> SpeakLine
    NextLine -- No --> ScoreSummary[Lines Learned Summary]
    ScoreSummary --> PracticeComplete([Session Saved Locally])
```

---

## 4. Camera Recording & Interruption Lifecycle

Ensures monotonic hardware clock tracking, take duration integrity, and crash-resilient storage.

```mermaid
sequenceDiagram
    autonumber
    actor Actor
    participant UI as ShootViews
    participant Controller as CameraController
    participant Clock as Hardware Clock (CACurrentMediaTime)
    participant Disk as MediaStore (Documents/audition-id/)
    participant Store as AppStore

    Actor->>UI: Tap Record (or say "Action")
    UI->>Controller: startRecording()
    Controller->>Clock: Sample startClock = CACurrentMediaTime()
    Controller->>Disk: Open QuickTime Movie Output (.mov)
    
    Note over Controller,Clock: Elapsed time computed via CACurrentMediaTime() - startClock (0.000s drift)

    alt Interruption (Phone Call / Lock Screen)
        Controller->>Controller: captureSessionWasInterrupted
        Controller->>Disk: Finalize partial movie file
        Controller->>UI: Notify interruption handled
    else Normal Stop
        Actor->>UI: Hold-to-Stop (or say "Cut")
        UI->>Controller: stopRecording()
    end

    Controller->>Disk: Query true AVURLAsset.duration
    Controller->>Store: Add Take(fileURL, duration, takeNumber)
    Store->>Store: persist() with monotonic sequence order
    Store->>UI: Display review sheet with exact take duration
```

---

## 5. Submission & Sharing Workflow

Only **Share Link** and **Separate Elements** are supported export formats.

```mermaid
flowchart TD
    PackageView([Package Screen]) --> SelectExport{Export Option}
    
    SelectExport -- 1. Share Link --> UploadiCloud[Upload to iCloud Ubiquity Container]
    UploadiCloud --> WaitForUpload[Wait for Ubiquitous Item Upload]
    WaitForUpload --> PublishURL[NSFileManager.urlForPublishingUbiquitousItem]
    PublishURL --> SaveFolderURL[Persist shareUbiquityFolderURL in Audition]
    SaveFolderURL --> DisplayLink[Display Copyable Link & Expiration Date]
    
    SelectExport -- 2. Separate Elements --> CompileZIP[ZipArchive: Streaming System zlib CRC32]
    CompileZIP --> BuildPackage[Compile Slate.mp4, Scenes.mp4, Headshot.jpg]
    BuildPackage --> WriteArchive[Write _SEPARATE.zip to Documents/Exports/]
    WriteArchive --> OpenShareSheet[Invoke UIActivityViewController Share Sheet]

    DisplayLink --> CompleteSubmission([Mark Audition as Sent])
    OpenShareSheet --> CompleteSubmission
```
