package com.chhunly.typer

import android.app.Activity
import android.os.Bundle
import android.text.Editable
import android.text.InputType
import android.text.TextWatcher
import android.view.inputmethod.EditorInfo
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.TextView

/**
 * Debug builds only: one field of each kind the Keyboard treats differently, for android/e2e.sh. Each field is
 * found by its content description; a password field's text is hidden from accessibility, so it is echoed in a
 * plain TextView ("password echo") for the test to read.
 */
class FieldsActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(32, 160, 32, 32)
            fitsSystemWindows = true
        }
        fun field(label: String, type: Int, options: Int = 0) = EditText(this).apply {
            contentDescription = label
            hint = label
            inputType = type
            imeOptions = options
            root.addView(this)
        }
        val echo = TextView(this).apply { contentDescription = "password echo" }
        field("password", InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD).addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {}
            override fun afterTextChanged(s: Editable?) {
                echo.text = s?.toString() ?: ""
            }
        })
        root.addView(echo)
        field("email", InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS)
        field("url", InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_URI, EditorInfo.IME_ACTION_GO)
        field("search", InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_CAP_SENTENCES, EditorInfo.IME_ACTION_SEARCH)
        field("incognito", InputType.TYPE_CLASS_TEXT, EditorInfo.IME_FLAG_NO_PERSONALIZED_LEARNING)
        setContentView(root)
    }
}
