import CreateML
import Foundation

// MARK: - Script Element Classifier Training Script
// Trains a native Core ML multiclass text classifier for screenplay element recognition:
// 1. scene_heading
// 2. character_cue
// 3. dialogue
// 4. parenthetical
// 5. action
// 6. metadata

print("Building screenplay element training dataset...")

var trainingData: [(String, String)] = []

func addExamples(_ label: String, _ items: [String]) {
    for item in items {
        let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            trainingData.append((item, label))
        }
    }
}

// 1. Scene Headings (Sluglines)
let scenePrefixes = ["INT.", "EXT.", "INT./EXT.", "INT/EXT", "I/E"]
let locations = [
    "COFFEE SHOP", "STREET CORNER", "APARTMENT", "PARK", "CAR", "CAFÉ", "STREET", "KITCHEN",
    "SUBWAY ENTRANCE", "HOSPITAL ROOM", "BEACH", "POLICE STATION", "DINER", "ALLEYWAY", "OFFICE",
    "ROOFTOP", "WAREHOUSE", "HOTEL LOBBY", "BASEMENT", "COURTROOM", "ELEVATOR", "BEDROOM", "LIBRARY",
    "AIRPORT TERMINAL", "PARKING LOT", "GAS STATION", "BAR", "AUDITORIUM", "MOTEL ROOM", "PENTHOUSE"
]
let timesOfDay = [
    "DAY", "NIGHT", "CONTINUOUS", "SAME", "MOMENTS LATER", "MORNING", "EVENING", "SUNSET", "DAWN", "DUSK", "LATER"
]

for loc in locations {
    for time in timesOfDay {
        let prefix = scenePrefixes.randomElement()!
        addExamples("scene_heading", [
            "\(prefix) \(loc) - \(time)",
            "\(prefix) \(loc) — \(time)",
            "\(prefix) \(loc) -- \(time)"
        ])
    }
}

for i in 1...30 {
    addExamples("scene_heading", [
        "SCENE \(i)",
        "Scene \(i):",
        "SC. \(i) - MAIN ROOM",
        "SCENE \(i): THE APARTMENT",
        "SCENE \(i) — INT. OFFICE"
    ])
}

addExamples("scene_heading", [
    "INT. COFFEE SHOP - DAY",
    "EXT. STREET CORNER - NIGHT",
    "INT. APARTMENT - CONTINUOUS",
    "EXT. PARK - SUNSET",
    "INT./EXT. CAR - MOVING",
    "INT./EXT. CAR - MOVING - DAY",
    "INT/EXT CAR - MOVING",
    "INT. CAFÉ — DAY",
    "EXT. STREET — NIGHT",
    "INT. KITCHEN — DAY",
    "SC. 14A — KITCHEN",
    "ACT I",
    "ACT II",
    "ACT III",
    "ACT IV",
    "ACT V",
    "ACT ONE",
    "ACT TWO",
    "ACT TWO SCENE FIVE",
    "ACT I SCENE 1",
    "EXT. SUBWAY PLATFORM - NIGHT",
    "INT. ELEVATOR - CONTINUOUS",
    "INT./EXT. POLICE CRUISER - DAY",
    "INT. POLICE STATION - INTERROGATION ROOM - DAY",
    "EXT. ALLEYWAY - NIGHT (RAINING)"
])

// 2. Character Cues
let characterNames = [
    "MAYA", "ARJUN", "DANNY", "SANDY", "SARAH", "JOHN", "DETECTIVE MILLER", "DR. KLINE",
    "OFFICER", "WAITER", "YOUNG WOMAN", "NURSE", "COP #1", "BARISTA", "SANDRA DEE", "LUCAS",
    "NATHAN", "DETECTIVE REYES", "DOCTOR", "JUDGE", "SECRETARY", "GUARD", "PARAMEDIC",
    "AGENT SMITH", "DR. WATSON", "MADAME CHEN", "FATHER THOMAS", "MR. HENDERSON", "MRS. PATEL",
    "COACH", "REPORTER #1", "SECURITY GUARD", "ELIZABETH", "MICHAEL", "DAVID", "RACHEL",
    "EMILY", "JAMES", "ROBERT", "MARY", "JENNIFER", "WILLIAM", "THOMAS", "CHARLES", "PATRICIA",
    "LINDA", "BARBARA", "RICHARD", "JOSEPH", "SUSAN", "JESSICA", "KAREN", "NANCY", "LISA",
    "BETTY", "MARGARET", "SANDRA", "ASHLEY", "KIMBERLY", "DONNA", "MICHELLE", "CAROL", "AMANDA",
    "MELISSA", "DEBORAH", "STEPHANIE", "REBECCA", "SHARON", "LAURA", "CYNTHIA", "KATHLEEN", "AMY",
    "SHIRLEY", "ANGELA", "HELEN", "ANNA", "BRENDA", "PAMELA", "NICOLE", "SAMANTHA", "KATHERINE",
    "CHRISTINE", "DEBRA", "CAROLYN", "JANET", "MARIA", "HEATHER", "DIANE", "JULIE", "JOYCE",
    "VICTORIA", "KELLY", "CHRISTINA", "LAUREN", "JOAN", "EVELYN", "OLIVIA", "JUDITH", "MEGAN",
    "CHERYL", "ANDREA", "HANNAH", "MARTHA", "JACQUELINE", "FRANCES", "GLORIA", "ANN", "TERESA",
    "KATHRYN", "SARA", "JANICE", "JEAN", "ALICE", "MADISON", "DORIS", "ABIGAIL", "JULIA", "JUDY",
    "GRACE", "DENISE", "AMBER", "MARILYN", "BEVERLY", "DANIELLE", "THERESA", "SOPHIA", "MARIE",
    "DIANA", "BRITTANY", "NATALIE", "ISABELLA", "CHARLOTTE", "ROSE", "ALEXIS", "KAYLA", "ALEX",
    "BEN", "CARTER", "DANIEL", "ETHAN", "FELIX", "GABRIEL", "HENRY", "IAN", "JACK", "KEVIN",
    "LEO", "MAX", "OLIVER", "PETER", "QUINN", "RYAN", "SAM", "TYLER", "VICTOR", "WILL", "ZACH",
    "KAT", "BARTENDER", "PATTY", "Female Lead", "Male Lead", "DET. CONNER", "OFFICER DAVIS"
]

let cueExtensions = ["", " (CONT'D)", " (O.S.)", " (V.O.)", " (O.C.)", ":", " (CONT'D):", " (PRE-LAP)"]
let cueIndents = ["", "\t", "\t\t", "   ", "    ", "      "]

for name in characterNames {
    for ext in cueExtensions {
        let ind = cueIndents.randomElement()!
        trainingData.append(("\(ind)\(name)\(ext)", "character_cue"))
    }
}

// 3. Parentheticals
let parentheticalPhrases = [
    "whispers", "whispering", "beat", "pauses", "pause", "smiling", "smiles", "crying", "laughs", "laughing",
    "sarcastic", "softly", "quietly", "hesitates", "hesitating", "firmly", "under her breath", "under his breath",
    "gently", "coldly", "screaming", "looking away", "turning around", "overlapping", "into phone", "clears throat",
    "shrugs", "sighs", "gasps", "points", "pointing", "nodding", "nods", "shaking head", "to Arjun", "to Maya",
    "to Danny", "to Sandy", "to Sarah", "to John", "to himself", "to herself", "out loud", "deadpan", "mocking",
    "pleading", "angrily", "sighing deeply", "pointing at Danny", "tearfully", "urgent", "terrified", "nervously",
    "turning to Maya", "standing up", "sitting down", "checking watch", "soft-spoken", "staring", "wryly",
    "reaches for glass", "in Spanish", "subtitled", "without looking up", "hushed tone", "furious", "chuckling"
]

for phrase in parentheticalPhrases {
    for indent in ["", "\t", "  ", "    "] {
        trainingData.append(("\(indent)(\(phrase))", "parenthetical"))
    }
}

// 4. Action Lines (Narrative scene directions)
let actionSentences = [
    "Maya paces across the room, clutching her phone.",
    "He glances out the rain-streaked window.",
    "Silence hangs in the cold air.",
    "She slams the door shut.",
    "They exchange uneasy glances.",
    "Maya sits at the counter, nervously tapping her fingers.",
    "Maya looks away, fighting back tears.",
    "Danny walks over to the jukebox and kicks it.",
    "Sandy turns around in disbelief.",
    "A loud explosion rocks the building.",
    "The car screeches to a sudden halt.",
    "He pulls out a crumpled envelope from his coat pocket.",
    "Dark clouds roll across the twilight sky.",
    "She picks up the wine glass and takes a slow sip.",
    "The room is dimly lit by a single desk lamp.",
    "Smoke fills the narrow corridor.",
    "He turns to leave, but hesitates at the threshold.",
    "She kneels beside the fallen bicycle.",
    "A heavy silence settles between them.",
    "He checks his wristwatch impatiently.",
    "She rummages through the cardboard box.",
    "The train pulls away into the darkness.",
    "A dog barks frantically in the distance.",
    "He drops the keys onto the glass coffee table.",
    "She stares down at the positive pregnancy test.",
    "The rain pours relentlessly against the windowpane.",
    "The door creaks open slowly.",
    "He fumbles with the lock in the dark.",
    "She wipes a tear from her cheek.",
    "He stands up abruptly, knocking over the chair.",
    "She reaches into her purse and pulls out a revolver.",
    "A cold gust of wind blows through the shattered window.",
    "They walk down the deserted corridor together.",
    "He stares at his own reflection in the cracked mirror.",
    "She places the steaming mug on the wooden table.",
    "The lights flicker once, then cut out completely.",
    "He lights a cigarette with trembling hands.",
    "She closes her eyes and takes a deep breath.",
    "Footsteps echo from the floor above.",
    "He pulls the curtains shut and backs away.",
    "A distant siren wails through the empty streets.",
    "She folds the letter and slides it under the book.",
    "He leans back in his leather chair, crossing his arms.",
    "The grandfather clock chimes midnight in the hall.",
    "She unlocks the heavy wooden door with trembling hands.",
    "He sets his briefcase on the polished mahogany desk.",
    "A waitress approaches their booth with a glass pot of hot coffee.",
    "The computer screen casts an eerie blue glow across his tired face.",
    "She glances around the diner, making sure no one is listening.",
    "He rubs his weary eyes, exhaustion etched deep into his features."
]

for sentence in actionSentences {
    for prefix in ["", "  ", "    "] {
        trainingData.append(("\(prefix)\(sentence)", "action"))
    }
}

// 5. Dialogue (Spoken lines)
let spokenLines = [
    "Where were you last night?",
    "I didn't think you'd come.",
    "Look at me.",
    "I told you everything I know.",
    "Not here. We can't talk here.",
    "Why did you do it?",
    "You're late.",
    "I know. Traffic.",
    "Wait!",
    "Hi.",
    "Hello.",
    "Bye.",
    "I have the letter.",
    "I still have it.",
    "Give it to me.",
    "I don't think we should do this.",
    "Look at me, I'm Sandra Dee.",
    "What did you tell them?",
    "Don't look now.",
    "I can't do this anymore.",
    "Did you see anyone else out there?",
    "Please, you have to believe me.",
    "What are we going to tell them?",
    "It's not what you think.",
    "Call the police right now!",
    "I'm sorry, I really am.",
    "Are you completely out of your mind?",
    "Don't touch that.",
    "What time does the train leave?",
    "I never wanted any of this to happen.",
    "Just listen to me for one second.",
    "How could you do this to us?",
    "There must be another explanation.",
    "We need to get out of here before they return.",
    "Nobody knows except the three of us.",
    "Is that why you called me?",
    "I thought we had an agreement.",
    "Tell me the truth, just once.",
    "You don't understand what they're capable of.",
    "I did what I had to do.",
    "Leave me alone.",
    "Are you coming with us or not?",
    "Nothing makes sense anymore.",
    "I will never forgive you for this.",
    "Who told you that?",
    "Meet me at the station at midnight.",
    "Take whatever you want and leave.",
    "That is none of your business.",
    "Everything is going to be fine.",
    "Do you remember what you promised me?",
    "I can explain everything.",
    "It was an accident.",
    "Stop talking and listen.",
    "Who was that on the phone?",
    "We have to go. Now.",
    "I swear I didn't see anything.",
    "What do you want from me?",
    "You know that's not true.",
    "I waited for two hours.",
    "Don't lie to me.",
    "Everything is going to change.",
    "Are you sure about this?",
    "I can't let you do that.",
    "Is everyone okay?",
    "We don't have much time.",
    "Where is the money?",
    "I never said that.",
    "Trust me on this.",
    "Why are you doing this?",
    "I believe you."
]

for line in spokenLines {
    for prefix in ["", "  ", "    ", "\t"] {
        trainingData.append(("\(prefix)\(line)", "dialogue"))
    }
}

// 6. Metadata
let metadataLines = [
    "CONFIDENTIAL", "PAGE 4 OF 12", "PAGE 1", "PAGE 2", "PAGE 3", "PAGE 5", "PAGE 10", "PAGE 24",
    "PAGE 15 OF 30", "AUDITION SIDES ONLY", "FINAL SHOOTING DRAFT", "SCENE END", "DRAFT 3", "DRAFT 4",
    "SECOND DRAFT", "REVISED DRAFT", "REV. 10/12/26", "DO NOT DISTRIBUTE", "FOR AUDITION PURPOSES ONLY",
    "WATERMARK: JANE DOE", "EPISODE 101 - PILOT", "YELLOW REVISED PAGES", "PINK REVISIONS - 11/04/26",
    "PROPERTY OF WARNER BROS", "ALL RIGHTS RESERVED", "CASTING COPY", "SIDES ONLY", "CONTINUED:", "(MORE)",
    "END OF EPISODE", "REVISED PAGES - 10/14", "DRAFT 1.2", "PRODUCTION DRAFT", "TABLE READ DRAFT",
    "RATE OF PAY: PRINCIPAL ROLE $1,500/DAY", "VIDEO USAGE: Internal training only. No broadcast.",
    "CASTING CALL — COMMERCIAL", "Submit a self-tape by email. Include a headshot and resume.",
    "DIRECTED BY:", "WRITTEN BY:", "COPYRIGHT 2026", "END OF SIDES", "SCENE 1 END", "ACT END",
    "CASTING CALL", "CASTING", "CALL", "OPEN CALL",
    "REQUIREMENT:", "REQUIREMENT :", "REQUIREMENTS:", "REQUIREMENTS :",
    "GENDER : MALE", "GENDER: MALE", "GENDER : FEMALE", "GENDER: FEMALE",
    "• GENDER: MALE", "• GENDER : MALE", "• GENDER: FEMALE",
    "AGE : (30-55 YEARS)", "AGE: (30-55 YEARS)", "AGE: 30-55", "AGE: 20-30 YEARS",
    "• AGE : (30-55 YEARS)", "• AGE: (30-55 YEARS)",
    "LANGUAGE : HINDI, ENGLISH & PUNJABI", "LANGUAGE: HINDI, ENGLISH & PUNJABI",
    "• LANGUAGE : HINDI, ENGLISH & PUNJABI", "• LANGUAGE: HINDI, ENGLISH & PUNJABI",
    "MUST WEAR A TURBAN", "• MUST WEAR A TURBAN",
    "WE'RE LOOKING FOR SIKH ACTORS", "WE ARE LOOKING FOR SIKH ACTORS",
    "BASED IN BHOPAL FOR AN UPCOMING PROJECT", "UPCOMING PROJECT", "BASED IN MUMBAI",
    "KINDLY SEND IN YOUR", "SEND IN YOUR", "PLEASE SEND YOUR PROFILES",
    "CONTACT NUMBER", "• CONTACT NUMBER",
    "DETAILED INTRODUCTION", "• DETAILED INTRODUCTION",
    "RECENT PICTURES", "• RECENT PICTURES", "RECENT PHOTOS",
    "MUKESH CHHABRA CASTING COMPANY", "MUKESH CHHABRA", "CASTING COMPANY",
    "ojas@mccc.in", "nupur@mccc.in", "casting@mccc.in", "auditions@agency.com",
    "WHAT TO SUBMIT", "HOW TO SUBMIT", "SUBMISSION DETAILS", "DEADLINE : 5 PM",
    "PLEASE ATTACH HEADSHOT AND RESUME", "NO PHONE CALLS PLEASE"
]

for meta in metadataLines {
    for prefix in ["", "  ", "\t\t"] {
        trainingData.append(("\(prefix)\(meta)", "metadata"))
    }
}

print("Total training examples: \(trainingData.count)")

let table = try MLDataTable(dictionary: [
    "text": trainingData.map { $0.0 },
    "label": trainingData.map { $0.1 }
])

print("Training MLTextClassifier...")
let classifier = try MLTextClassifier(trainingData: table, textColumn: "text", labelColumn: "label")

let outputDirectory = URL(fileURLWithPath: "OneTake/Core/Models")
let outputURL = outputDirectory.appendingPathComponent("ScriptElementClassifier.mlmodel")

try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let metadata = MLModelMetadata(
    author: "OneTake",
    shortDescription: "Multiclass screenplay element classifier for headings, cues, dialogue, parentheticals, actions, and metadata.",
    version: "1.0.0"
)

try classifier.write(to: outputURL, metadata: metadata)
print(" Successfully trained and exported model to \(outputURL.path)")
