package com.chhunly.typer.app

/** One Setup step: [button] is null for the last step, which points at the Try it field. */
data class Step(val title: String, val detail: String, val button: String?)

data class Feature(val title: String, val detail: String)

/**
 * The Companion app's copy in Khmer and English. The app has its own switch (stored in preferences) rather
 * than following the phone's language, as on iOS. Android menu names stay in English, as on the phone.
 */
data class Copy(
    val tagline: String,
    val setupTitle: String,
    val steps: List<Step>,
    val done: String,
    val tryTitle: String,
    val tryHint: String,
    val featuresTitle: String,
    val features: List<Feature>,
    val aboutTitle: String,
    val about: String,
    val languageKhmer: String,
    val languageEnglish: String,
) {
    companion object {
        val khmer = Copy(
            tagline = "វាយខ្មែរ ដូចពេលអ្នកឆាត។",
            setupTitle = "ការរៀបចំ",
            steps = listOf(
                Step("បើក Typer", "Settings › System › Keyboard › On-screen keyboard ហើយបើក Typer (សរសេរ)", "បើក Settings"),
                Step("ជ្រើស Typer", "ចុចប៊ូតុង ហើយជ្រើស Typer (សរសេរ)", "ជ្រើសក្តារចុច"),
                Step("ចាប់ផ្តើមវាយ", "សាកវាយនៅខាងក្រោម៖ វាយ knhom ហើយចុច ខ្ញុំ", null),
            ),
            done = "រួចរាល់",
            tryTitle = "សាកវាយ",
            tryHint = "knhom tov sala rean",
            featuresTitle = "មុខងារ",
            features = listOf(
                Feature("វាយដូចពេលឆាត", "វាយអក្សរឡាតាំងទាំងឃ្លា ហើយ Typer ប្តូរវាជាខ្មែរ។"),
                Feature("សរសេរតាមរបៀបអ្នក", "គ្មានច្បាប់តឹងរ៉ឹងទេ៖ nh, knh ឬ knhom សុទ្ធតែបាន ខ្ញុំ។"),
                Feature("ចាំអ្វីដែលអ្នកជ្រើស", "ពាក្យដែលអ្នកជ្រើសញឹកញាប់ នឹងឡើងមកមុនគេ។"),
                Feature("របារពាក្យស្នើ", "អក្សរដិត៖ ពាក្យស្នើល្អបំផុត។ abc៖ រក្សាអក្សរឡាតាំង។ លេខ៖ មើលពាក្យស្នើទាំងអស់។"),
                Feature("ខ្មែរ ឬ អង់គ្លេស", "ចុចគ្រាប់ ខ ដើម្បីប្តូរទៅវាយអង់គ្លេសធម្មតា។"),
            ),
            aboutTitle = "ទូរស័ព្ទរបស់អ្នក ទិន្នន័យរបស់អ្នក",
            about = "Typer មិនប្រើអ៊ីនធឺណិតទេ ហើយអ្វីដែលអ្នកវាយ មិនចេញពីទូរស័ព្ទរបស់អ្នកឡើយ។ " +
                "Android នឹងព្រមានថា ក្តារចុចណាមួយអាចប្រមូលអ្វីដែលអ្នកវាយ។ Typer រក្សាទុកអ្វីៗទាំងអស់នៅលើទូរស័ព្ទនេះ។",
            languageKhmer = "ភាសា៖ ខ្មែរ",
            languageEnglish = "ភាសា៖ អង់គ្លេស",
        )

        val english = Copy(
            tagline = "Type Khmer the way you chat.",
            setupTitle = "Setup",
            steps = listOf(
                Step("Turn on Typer", "Settings › System › Keyboard › On-screen keyboard, then turn on Typer (សរសេរ)", "Open Settings"),
                Step("Choose Typer", "Tap the button and pick Typer (សរសេរ)", "Choose keyboard"),
                Step("Start typing", "Try it below: type knhom and tap ខ្ញុំ", null),
            ),
            done = "Done",
            tryTitle = "Try it",
            tryHint = "knhom tov sala rean",
            featuresTitle = "Features",
            features = listOf(
                Feature("Type how you chat", "Type a whole phrase in Latin letters and Typer turns it into Khmer."),
                Feature("Spell it your way", "No strict rules: nh, knh or knhom all give ខ្ញុំ."),
                Feature("Learns your picks", "Words you pick often come up first."),
                Feature("The Suggestion bar", "Bold: the top Suggestion. abc: keep the Latin. The number: see every Suggestion."),
                Feature("Khmer or English", "Tap the ខ key to switch to plain English typing."),
            ),
            aboutTitle = "Your phone, your words",
            about = "Typer has no internet access, and nothing you type leaves your phone. " +
                "Android warns that any keyboard could collect what you type; Typer keeps everything on this phone.",
            languageKhmer = "Language: Khmer",
            languageEnglish = "Language: English",
        )
    }
}
