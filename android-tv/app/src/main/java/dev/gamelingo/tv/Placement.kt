package dev.gamelingo.tv

enum class Placement(val title: String) {
    BOTTOM("أسفل الشاشة"), TOP("أعلى الشاشة"), CENTER("وسط الشاشة");
    fun next() = values()[(ordinal + 1) % values().size]
    companion object {
        fun from(value: String?) = values().firstOrNull { it.name == value } ?: BOTTOM
    }
}

const val SAMPLE = "اختبار ترجمة الألعاب — GameLingo"
