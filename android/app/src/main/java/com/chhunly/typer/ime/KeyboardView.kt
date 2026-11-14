package com.chhunly.typer.ime

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.Typeface
import android.graphics.drawable.Drawable
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.text.TextPaint
import android.text.TextUtils
import android.view.HapticFeedbackConstants
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.WindowInsets
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityManager
import android.view.accessibility.AccessibilityNodeInfo
import android.view.accessibility.AccessibilityNodeProvider
import com.chhunly.typer.R
import com.chhunly.typer.core.Box
import com.chhunly.typer.core.Key
import com.chhunly.typer.core.KeyAction
import com.chhunly.typer.core.KeyEffect
import com.chhunly.typer.core.KeyLayout
import com.chhunly.typer.core.KeyPage
import com.chhunly.typer.core.KeyStyle
import com.chhunly.typer.core.KeyTouches
import com.chhunly.typer.core.Metrics
import com.chhunly.typer.core.StripAction
import com.chhunly.typer.core.StripLayout
import com.chhunly.typer.core.StripSlot
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/**
 * The whole Keyboard: one custom-drawn View (ADR 0004). Keys come from [KeyLayout] in dp, touches go through
 * [KeyTouches], colours from [KeyboardTheme]. The view only draws and reports; the service decides what keys do.
 */
@SuppressLint("ViewConstructor")
class KeyboardView(context: Context, private val listener: Listener) : View(context) {
    interface Listener {
        fun onKey(action: KeyAction)
        fun onHint(text: String)
        fun onStrip(action: StripAction)
        /** A row of the all-Suggestions panel: a Suggestion index, or -1 for the Latin row. */
        fun onPanel(index: Int)
        fun onDragStart()
        fun onCaret(clusters: Int)
        fun onDragEnd()
    }

    enum class Shift { OFF, ONCE, LOCK }

    enum class ReturnKind(val label: String, val icon: Int) {
        NEWLINE("return", R.drawable.ic_return),
        SEARCH("search", R.drawable.ic_search),
        SEND("send", R.drawable.ic_send),
        GO("go", R.drawable.ic_go),
        NEXT("next", R.drawable.ic_go),
        PREVIOUS("previous", R.drawable.ic_go),
        DONE("done", R.drawable.ic_done),
    }

    data class State(
        val page: KeyPage = KeyPage.LETTERS,
        val shift: Shift = Shift.OFF,
        val mode: String = "ខ",
        val canToggle: Boolean = true,
        /** The Phrase as typed; empty when not composing. */
        val typed: String = "",
        val suggestions: List<String> = emptyList(),
        /** English mode: [typed word, best, second]; empty hides them. */
        val words: List<String> = emptyList(),
        val showAll: Boolean = false,
        val returnKind: ReturnKind = ReturnKind.NEWLINE,
        /** The field has an action (search, send, ...): the return key is drawn in primary. */
        val returnAction: Boolean = false,
    ) {
        val composing get() = typed.isNotEmpty()
        val panelOpen get() = showAll && composing
    }

    var state = State()
        set(value) {
            if (field == value) return
            val relayout = field.page != value.page || (field.shift != Shift.OFF) != (value.shift != Shift.OFF)
            if (field.panelOpen != value.panelOpen) panelScroll = 0f
            field = value
            if (relayout) keysCache = null
            invalidate()
        }

    var theme: KeyboardTheme = KeyboardTheme.from(context)
        set(value) {
            field = value
            invalidate()
        }

    private val d = resources.displayMetrics.density
    /** px per sp, following the user's font size setting. */
    /** Kantumruy Pro (SIL OFL), Typer's font for Khmer and Latin; a variable font, so weights are set per draw. */
    private val kantumruy: Typeface? = if (Build.VERSION.SDK_INT >= 26) runCatching { resources.getFont(R.font.kantumruy_pro) }.getOrNull() else null

    private fun font(bold: Boolean) {
        val k = kantumruy
        if (k != null && Build.VERSION.SDK_INT >= 26) {
            text.typeface = k
            text.fontVariationSettings = if (bold) "'wght' 700" else "'wght' 450"
        } else {
            text.typeface = if (bold) Typeface.DEFAULT_BOLD else Typeface.DEFAULT
        }
    }

    private val sp = android.util.TypedValue.applyDimension(android.util.TypedValue.COMPLEX_UNIT_SP, 1f, resources.displayMetrics)
    private var metrics = Metrics(360f, 800f)
    private var keysCache: List<Key>? = null
    private val keys: List<Key>
        get() = keysCache ?: KeyLayout.keys(metrics, state.page, state.shift != Shift.OFF).also { keysCache = it }

    /** The navigation bar (or gesture area) under the keys, in px; the background is drawn behind it. */
    private var bottomInset = 0

    private val tracker = KeyTouches(step = 10f)
    private val handler = Handler(Looper.getMainLooper())
    private var repeating: Runnable? = null
    private var longPressing: Runnable? = null
    /** The long-press bubble: the key and its hint, shown until the finger lifts. */
    private var longShown: Pair<Key, String>? = null

    // strip and panel touches (one finger)
    private var stripDown: StripSlot? = null
    /** The finger that owns the strip or panel touch; other fingers can't end it. */
    private var ownPointer = -1
    private var panelDownY = -1f
    private var panelLastY = 0f
    private var panelScrolling = false
    private var panelScroll = 0f
    private val slop = ViewConfiguration.get(context).scaledTouchSlop

    init {
        isHapticFeedbackEnabled = true
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_YES
    }

    // ---- size ----

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val w = MeasureSpec.getSize(widthMeasureSpec)
        val screenH = resources.displayMetrics.heightPixels / d
        val m = Metrics(w / d, screenH)
        if (m.width != metrics.width || m.pitch != metrics.pitch) {
            metrics = m
            keysCache = null
        }
        setMeasuredDimension(w, (metrics.height * d).toInt() + bottomInset)
    }

    override fun onApplyWindowInsets(insets: WindowInsets): WindowInsets {
        // With gesture navigation the system draws its own bar for the Keyboard (hide and switch buttons, 48 dp):
        // that is a tappable element, taller than the navigation bar inset. Keep the keys clear of both.
        val bottom = if (Build.VERSION.SDK_INT >= 30) {
            maxOf(insets.getInsets(WindowInsets.Type.navigationBars()).bottom, insets.getInsets(WindowInsets.Type.tappableElement()).bottom)
        } else {
            @Suppress("DEPRECATION") insets.systemWindowInsetBottom
        }
        if (bottom != bottomInset) {
            bottomInset = bottom
            requestLayout()
        }
        return insets
    }

    /** Height of the keys and strip, without the navigation bar inset (px). */
    val keyboardHeight: Int get() = (metrics.height * d).toInt()

    // ---- drawing ----

    private val fill = Paint(Paint.ANTI_ALIAS_FLAG)
    private val text = TextPaint(Paint.ANTI_ALIAS_FLAG).apply { textAlign = Paint.Align.CENTER }
    private val rect = RectF()
    private val bounds = Rect()
    private val icons = HashMap<Int, Drawable>()

    private fun px(v: Float) = v * d
    private fun rectOf(b: Box, inset: Float = 0f) =
        rect.apply { set(px(b.left) + inset, px(b.top) + inset, px(b.right) - inset, px(b.bottom) - inset) }

    override fun onDraw(canvas: Canvas) {
        canvas.drawColor(theme.background)
        drawStrip(canvas)
        if (state.panelOpen) drawPanel(canvas) else drawKeys(canvas)
    }

    private fun drawKeys(canvas: Canvas) {
        val pressed = tracker.pressed
        for (key in keys) drawKey(canvas, key, key in pressed)
        val shown = longShown
        if (shown != null) drawLongPress(canvas, shown.first, shown.second)
        else pressed.firstOrNull { previewed(it) }?.let { drawPreview(canvas, it) }
    }

    private fun previewed(key: Key) = key.action is KeyAction.Text

    private fun keyColors(key: Key): Pair<Int, Int> = when (key.style) {
        KeyStyle.LETTER -> theme.letterKey to theme.onLetter
        KeyStyle.FUNCTION -> theme.functionKey to theme.onFunction
        KeyStyle.MODE -> theme.mode to theme.onMode
        KeyStyle.ACTION -> if (state.returnAction) theme.action to theme.onAction else theme.functionKey to theme.onFunction
    }

    private fun drawKey(canvas: Canvas, key: Key, pressed: Boolean) {
        val (bg, fg) = keyColors(key)
        val r = rectOf(key.box)
        val pill = key.action == KeyAction.Page || key.action == KeyAction.Return
        val radius = if (pill) r.height() / 2 else px(metrics.radius)
        val alpha = if (key.action == KeyAction.Mode && !state.canToggle) 102 else 255  // dimmed when it can't toggle
        fill.color = bg
        fill.alpha = alpha
        canvas.drawRoundRect(r, radius, radius, fill)
        if (pressed) {  // Material state layer: the "on" colour at 10%
            fill.color = fg
            fill.alpha = 26
            canvas.drawRoundRect(r, radius, radius, fill)
        }
        val cx = r.centerX()
        val cy = r.centerY()
        when (val a = key.action) {
            is KeyAction.Text -> {
                drawLabel(canvas, a.text, cx, cy, if (a.text.length == 1) 26f else 22f, fg, alpha, onBaseline = a.text.length == 1)
                key.hint?.let {
                    font(false)
                    text.textSize = 12f * sp
                    text.color = theme.onSurfaceVariant
                    text.textAlign = Paint.Align.RIGHT
                    canvas.drawText(it, r.right - px(4f), r.top + px(14f), text)
                    text.textAlign = Paint.Align.CENTER
                }
            }
            KeyAction.Shift -> drawIcon(canvas, when (state.shift) {
                Shift.OFF -> R.drawable.ic_shift
                Shift.ONCE -> R.drawable.ic_shift_on
                Shift.LOCK -> R.drawable.ic_caps_lock
            }, cx, cy, fg)
            KeyAction.Backspace -> drawIcon(canvas, R.drawable.ic_backspace, cx, cy, fg)
            KeyAction.Return -> drawIcon(canvas, state.returnKind.icon, cx, cy, fg)
            KeyAction.Page -> drawLabel(canvas, if (state.page == KeyPage.LETTERS) "?123" else "ABC", cx, cy, 16f, fg, alpha, bold = true)
            KeyAction.Symbols -> drawLabel(canvas, if (state.page == KeyPage.NUMBERS) "=\\<" else "?123", cx, cy, 16f, fg, alpha, bold = true)
            KeyAction.Mode -> drawLabel(canvas, state.mode, cx, cy, if (state.mode == "EN") 16f else 20f, fg, alpha, bold = true)
            KeyAction.Space -> Unit  // blank, like Gboard
        }
    }

    /** `onBaseline`: one shared baseline for single characters, so a row doesn't jump and `,` `.` sit low like text. */
    private fun drawLabel(canvas: Canvas, s: String, cx: Float, cy: Float, sizeSp: Float, color: Int, alpha: Int = 255, bold: Boolean = false, onBaseline: Boolean = false) {
        font(bold)
        text.textSize = sizeSp * sp
        text.color = color
        text.alpha = alpha
        text.getTextBounds(s, 0, s.length, bounds)
        val baseline = if (onBaseline) cy + text.textSize * 0.36f else cy - bounds.exactCenterY()
        canvas.drawText(s, cx, baseline, text)
        text.alpha = 255
    }

    private fun drawIcon(canvas: Canvas, id: Int, cx: Float, cy: Float, color: Int, sizeDp: Float = 24f) {
        val icon = icons.getOrPut(id) { context.getDrawable(id)!!.mutate() }
        val h = px(sizeDp) / 2
        icon.setBounds((cx - h).toInt(), (cy - h).toInt(), (cx + h).toInt(), (cy + h).toInt())
        icon.setTint(color)
        icon.draw(canvas)
    }

    /** The character above the finger: a round bubble sitting on the key (reference.md: about 57 dp on Gboard). */
    private fun bubble(key: Key): RectF {
        val size = min(48f, metrics.rowsTop - 4f)
        val cx = key.box.centerX
        val bottom = key.box.top - 2f
        return RectF(px(cx - size / 2), px(bottom - size), px(cx + size / 2), px(bottom))
    }

    private fun drawBubbleBackground(canvas: Canvas, r: RectF) {
        fill.color = 0x33000000
        canvas.drawOval(RectF(r.left, r.top + px(1.5f), r.right, r.bottom + px(1.5f)), fill)  // soft shadow
        fill.color = theme.popup
        canvas.drawOval(r, fill)
    }

    private fun drawPreview(canvas: Canvas, key: Key) {
        val label = (key.action as KeyAction.Text).text
        val r = bubble(key)
        drawBubbleBackground(canvas, r)
        drawLabel(canvas, label, r.centerX(), r.centerY(), 26f, theme.onLetter, onBaseline = label.length == 1)
    }

    /** Long press: the hint digit, selected (primary circle), as Gboard shows it. */
    private fun drawLongPress(canvas: Canvas, key: Key, hint: String) {
        val r = bubble(key)
        drawBubbleBackground(canvas, r)
        fill.color = theme.primary
        canvas.drawCircle(r.centerX(), r.centerY(), r.width() * 0.36f, fill)
        drawLabel(canvas, hint, r.centerX(), r.centerY(), 22f, theme.onAction)
    }

    // ---- strip ----

    private fun stripSlots(): List<StripSlot> = when {
        state.composing -> StripLayout.composing(metrics)
        state.words.isNotEmpty() -> StripLayout.words(metrics, state.words.size)
        else -> StripLayout.punctuation(metrics, if (state.mode == "EN") KeyLayout.englishPunctuation else KeyLayout.punctuation)
    }

    private fun stripLabel(a: StripAction): String = when (a) {
        is StripAction.Suggestion -> state.suggestions.getOrNull(a.index) ?: if (a.index == 0) state.typed else ""
        StripAction.Latin -> "abc"
        StripAction.Expand -> state.suggestions.size.toString()
        is StripAction.Punctuation -> a.text
        is StripAction.Word -> state.words.getOrNull(a.index)?.let { if (a.index == 0) "“$it”" else it } ?: ""
    }

    /** Typer yellow: the top Suggestion (or the Phrase itself until Suggestions arrive) and the best English word. */
    private fun emphasised(a: StripAction) = (a is StripAction.Suggestion && a.index == 0) || (a is StripAction.Word && a.index == 1)

    /**
     * The strip, as on iOS: pills. The top Suggestion (and the best English word) is Typer yellow with ink text in the
     * regular weight; abc,
     * the expand control, the other words and the punctuation keys sit on the function-key colour.
     */
    private fun drawStrip(canvas: Canvas) {
        val radius = px(8f)
        for (slot in stripSlots()) {
            val r = rectOf(slot.box)
            val a = slot.action
            val yellow = emphasised(a)
            val (bg, fg) = if (yellow) theme.mode to theme.onMode else theme.functionKey to theme.onFunction
            fill.color = bg
            canvas.drawRoundRect(r, radius, radius, fill)
            if (stripDown == slot) {  // pressed: the state layer, as on the keys
                fill.color = fg
                fill.alpha = 26
                canvas.drawRoundRect(r, radius, radius, fill)
                fill.alpha = 255
            }
            when (a) {
                StripAction.Expand -> {
                    drawLabel(canvas, stripLabel(a), r.centerX() - px(8f), r.centerY(), 16f, fg, bold = true)
                    drawIcon(canvas, if (state.showAll) R.drawable.ic_collapse else R.drawable.ic_expand, r.centerX() + px(11f), r.centerY(), fg, 18f)
                }
                StripAction.Latin -> drawLabel(canvas, "abc", r.centerX(), r.centerY(), 16f, fg, bold = true)
                else -> drawStripText(canvas, stripLabel(a), r, false, a is StripAction.Punctuation, fg, start = a is StripAction.Suggestion)  // regular weight: the yellow says it's the top one
            }
        }
    }

    /**
     * Strip text, sized for Khmer: stacked vowels and subscripts need about 1.9 em of height. Long text shrinks to 70%,
     * then loses its start (the end, where the user types, stays visible). `start`: aligned to the pill's left edge.
     */
    private fun drawStripText(canvas: Canvas, s: String, r: RectF, bold: Boolean, punct: Boolean, color: Int, start: Boolean = false) {
        if (s.isEmpty()) return
        val khmer = s.any { it in '\u1780'..'\u17FF' }
        val size = if (punct) 20f else 18f
        font(bold)
        text.color = color
        text.textSize = size * sp
        val pad = px(12f)
        val avail = r.width() - 2 * pad
        val w = text.measureText(s)
        if (w > avail) text.textSize = max(size * 0.7f * sp, text.textSize * avail / w)
        val shown = TextUtils.ellipsize(s, text, avail, TextUtils.TruncateAt.START).toString()
        if (start) {
            text.textAlign = Paint.Align.LEFT
            canvas.drawText(shown, r.left + pad, stripBaseline(r, khmer), text)
            text.textAlign = Paint.Align.CENTER
        } else {
            canvas.drawText(shown, r.centerX(), stripBaseline(r, khmer), text)
        }
    }

    /** One baseline per script and size, from a reference with the tallest stacks, so slots line up and never clip. */
    private fun stripBaseline(r: RectF, khmer: Boolean): Float {
        val ref = if (khmer) "ស្រឡាញ់ខ្ញុំ" else "Hgjy"
        text.getTextBounds(ref, 0, ref.length, bounds)
        return r.centerY() - bounds.exactCenterY()
    }

    // ---- all-Suggestions panel ----

    private val rowHeight get() = 52f
    private fun panelBox() = Box(0f, metrics.rowsTop, metrics.width, metrics.height - metrics.rowsTop)
    private fun panelRows() = state.suggestions.size + 1  // + the Latin row

    private fun drawPanel(canvas: Canvas) {
        val box = panelBox()
        val r = rectOf(box)
        canvas.save()
        canvas.clipRect(r)
        fill.color = theme.letterKey
        canvas.drawRoundRect(RectF(r.left + px(metrics.margin), r.top, r.right - px(metrics.margin), r.bottom - px(4f)), px(12f), px(12f), fill)
        for (i in 0 until panelRows()) {
            val top = r.top + px(i * rowHeight) - panelScroll
            if (top > r.bottom || top + px(rowHeight) < r.top) continue
            val row = RectF(r.left + px(metrics.margin), top, r.right - px(metrics.margin), top + px(rowHeight))
            val latin = i == state.suggestions.size
            text.textAlign = Paint.Align.RIGHT
            if (!latin) drawPanelText(canvas, (i + 1).toString(), row.left + px(28f), row, 14f, theme.onSurfaceVariant, false)
            text.textAlign = Paint.Align.LEFT
            val label = if (latin) state.typed else state.suggestions[i]
            drawPanelText(canvas, label, row.left + px(40f), row, 20f, theme.onLetter, i == 0 && !latin, row.right - px(if (latin) 64f else 12f))
            if (latin) {
                text.textAlign = Paint.Align.RIGHT
                drawPanelText(canvas, "abc", row.right - px(14f), row, 13f, theme.onSurfaceVariant, true)
            }
            text.textAlign = Paint.Align.CENTER
            fill.color = theme.outlineVariant
            canvas.drawRect(row.left + px(12f), row.bottom - px(0.5f), row.right - px(12f), row.bottom + px(0.5f), fill)
        }
        canvas.restore()
    }

    private fun drawPanelText(canvas: Canvas, s: String, x: Float, row: RectF, sizeSp: Float, color: Int, bold: Boolean, right: Float = row.right) {
        font(bold)
        text.textSize = sizeSp * sp
        text.color = color
        val avail = right - x
        val shown = if (text.textAlign == Paint.Align.LEFT && avail > 0) TextUtils.ellipsize(s, text, avail, TextUtils.TruncateAt.START).toString() else s
        canvas.drawText(shown, x, stripBaseline(row, s.any { it in 'ក'..'៿' }), text)
    }

    private fun panelIndexAt(yDp: Float): Int? {
        val i = ((yDp - metrics.rowsTop + panelScroll / d) / rowHeight).toInt()
        return if (yDp >= metrics.rowsTop && i in 0 until panelRows()) i else null
    }

    private fun maxScroll(): Float = max(0f, px(panelRows() * rowHeight) - px(panelBox().height - 4f))

    // ---- touch ----

    @SuppressLint("ClickableViewAccessibility")
    override fun onTouchEvent(e: MotionEvent): Boolean {
        val i = e.actionIndex
        val id = e.getPointerId(i)
        val x = e.getX(i) / d
        val y = e.getY(i) / d
        when (e.actionMasked) {
            MotionEvent.ACTION_DOWN, MotionEvent.ACTION_POINTER_DOWN -> when {
                y < metrics.rowsTop - 2f -> if (e.actionMasked == MotionEvent.ACTION_DOWN) {
                    stripDown = stripSlots().firstOrNull { it.box.contains(x, metrics.stripHeight / 2) }
                    ownPointer = id
                    invalidate()
                }
                state.panelOpen -> if (e.actionMasked == MotionEvent.ACTION_DOWN) {
                    ownPointer = id
                    panelDownY = e.getY(i)
                    panelLastY = panelDownY
                    panelScrolling = false
                }
                else -> KeyLayout.hit(x, y, keys)?.let { run(id, tracker.down(id, it, x)) }
            }
            MotionEvent.ACTION_MOVE -> {
                if (state.panelOpen && panelDownY >= 0) {
                    val py = e.findPointerIndex(ownPointer).let { if (it >= 0) e.getY(it) else panelLastY }
                    if (!panelScrolling && abs(py - panelDownY) > slop) panelScrolling = true
                    if (panelScrolling) {
                        panelScroll = (panelScroll - (py - panelLastY)).coerceIn(0f, maxScroll())
                        invalidate()
                    }
                    panelLastY = py
                } else {
                    for (p in 0 until e.pointerCount) {
                        val px = e.getX(p) / d
                        KeyLayout.hit(px, e.getY(p) / d, keys)?.let { run(e.getPointerId(p), tracker.move(e.getPointerId(p), it, px)) }
                    }
                }
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_POINTER_UP -> {
                val strip = stripDown
                val owner = id == ownPointer  // the strip or panel finger; any other finger is a key touch
                when {
                    owner && strip != null -> {
                        stripDown = null
                        invalidate()
                        if (strip.box.contains(x, y.coerceAtMost(metrics.stripHeight - 1f).coerceAtLeast(0f)) && y < metrics.rowsTop + 8f) {
                            haptic(HapticFeedbackConstants.KEYBOARD_TAP)
                            listener.onStrip(strip.action)
                        }
                    }
                    owner && panelDownY >= 0 -> {
                        panelDownY = -1f
                        if (!panelScrolling) panelIndexAt(y)?.let { row ->
                            haptic(HapticFeedbackConstants.KEYBOARD_TAP)
                            listener.onPanel(if (row == state.suggestions.size) -1 else row)
                        }
                    }
                    else -> KeyLayout.hit(x, y, keys)?.let { run(id, tracker.up(id, it)) }
                }
                if (e.actionMasked == MotionEvent.ACTION_UP) endTouches()
            }
            MotionEvent.ACTION_CANCEL -> {
                stripDown = null
                panelDownY = -1f
                for (p in 0 until e.pointerCount) run(e.getPointerId(p), tracker.cancel(e.getPointerId(p)))
                endTouches()
            }
        }
        invalidate()
        return true
    }

    private fun endTouches() {
        longShown = null
        longPressing?.let { handler.removeCallbacks(it) }
        longPressing = null
    }

    /** Stop everything in flight (the Keyboard hides or the field changes). */
    fun reset() {
        repeating?.let { handler.removeCallbacks(it) }
        repeating = null
        endTouches()
        run(-1, tracker.reset())
        stripDown = null
        panelDownY = -1f
        ownPointer = -1
        invalidate()
    }

    private fun run(id: Int, effects: List<KeyEffect>) {
        for (fx in effects) when (fx) {
            KeyEffect.Press -> haptic(HapticFeedbackConstants.KEYBOARD_TAP)
            is KeyEffect.Fire -> {
                if (Build.VERSION.SDK_INT >= 27) haptic(HapticFeedbackConstants.KEYBOARD_RELEASE)
                listener.onKey(fx.action)
            }
            KeyEffect.StartRepeat -> {
                val r = object : Runnable {
                    override fun run() {
                        listener.onKey(KeyAction.Backspace)
                        handler.postDelayed(this, REPEAT_INTERVAL)
                    }
                }
                repeating?.let { handler.removeCallbacks(it) }
                repeating = r
                handler.postDelayed(r, REPEAT_START)
            }
            KeyEffect.StopRepeat -> {
                repeating?.let { handler.removeCallbacks(it) }
                repeating = null
            }
            KeyEffect.StartLongPress -> {
                longPressing?.let { handler.removeCallbacks(it) }
                val r = Runnable {
                    longPressing = null
                    run(id, tracker.longPress(id))
                    invalidate()
                }
                longPressing = r
                handler.postDelayed(r, LONG_PRESS)
            }
            is KeyEffect.FireHint -> {
                haptic(HapticFeedbackConstants.LONG_PRESS)
                longShown = keys.firstOrNull { it.hint == fx.text }?.let { it to fx.text }
                listener.onHint(fx.text)
            }
            KeyEffect.DragStarted -> {
                haptic(HapticFeedbackConstants.KEYBOARD_TAP)
                listener.onDragStart()
            }
            is KeyEffect.MoveCaret -> listener.onCaret(fx.clusters)
            KeyEffect.DragEnded -> listener.onDragEnd()
        }
    }

    /** Key vibration from the Companion app ([HapticsChoice]); read when the Keyboard opens. */
    var haptics = HapticsChoice.SYSTEM

    private val vibrator: android.os.Vibrator? by lazy {
        if (Build.VERSION.SDK_INT >= 31) context.getSystemService(android.os.VibratorManager::class.java)?.defaultVibrator
        else @Suppress("DEPRECATION") context.getSystemService(Context.VIBRATOR_SERVICE) as? android.os.Vibrator
    }

    /**
     * SYSTEM follows the phone's touch-feedback setting (no FLAG_IGNORE_GLOBAL_SETTING), with a tap on press and a
     * lighter one on release. LIGHT and STRONG are a fixed tick or click on press only; OFF is silent.
     */
    private fun haptic(constant: Int) {
        when (haptics) {
            HapticsChoice.SYSTEM -> performHapticFeedback(constant)
            HapticsChoice.OFF -> Unit
            HapticsChoice.LIGHT, HapticsChoice.STRONG -> {
                if (Build.VERSION.SDK_INT >= 27 && constant == HapticFeedbackConstants.KEYBOARD_RELEASE) return
                val v = vibrator ?: return
                val strong = haptics == HapticsChoice.STRONG
                when {
                    Build.VERSION.SDK_INT >= 29 -> v.vibrate(android.os.VibrationEffect.createPredefined(
                        if (strong) android.os.VibrationEffect.EFFECT_CLICK else android.os.VibrationEffect.EFFECT_TICK))
                    Build.VERSION.SDK_INT >= 26 -> v.vibrate(android.os.VibrationEffect.createOneShot(if (strong) 18 else 8, if (strong) 200 else 70))
                    else -> @Suppress("DEPRECATION") v.vibrate(if (strong) 18L else 8L)
                }
            }
        }
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        reset()
    }

    // ---- accessibility: every key, strip slot and panel row is a virtual node with a label ----

    /** `key`: a Keyboard key (TalkBack reads just its label, as on other keyboards), else a strip or panel button. */
    private class Target(val id: Int, val label: String, val box: Box, val key: Boolean = false, val activate: () -> Unit)

    private fun targets(): List<Target> {
        val out = ArrayList<Target>()
        for ((i, s) in stripSlots().withIndex()) {
            val label = when (val a = s.action) {
                StripAction.Latin -> "abc, keep Latin"
                StripAction.Expand -> "all suggestions, ${state.suggestions.size}"
                else -> stripLabel(a)
            }
            if (label.isNotEmpty()) out += Target(STRIP + i, label, s.box) { listener.onStrip(s.action) }
        }
        if (state.panelOpen) {
            for (i in 0 until panelRows()) {
                val top = metrics.rowsTop + i * rowHeight - panelScroll / d
                if (top + rowHeight <= metrics.rowsTop || top >= metrics.height) continue
                val latin = i == state.suggestions.size
                val label = if (latin) "${state.typed}, keep Latin" else state.suggestions[i]
                out += Target(PANEL + i, label, Box(0f, max(top, metrics.rowsTop), metrics.width, rowHeight)) {
                    listener.onPanel(if (latin) -1 else i)
                }
            }
        } else {
            for ((i, k) in keys.withIndex()) out += Target(KEYS + i, describe(k), k.box, key = true) { listener.onKey(k.action) }
        }
        return out
    }

    private fun describe(k: Key): String = when (val a = k.action) {
        is KeyAction.Text -> when (a.text) {
            "," -> "comma"
            "." -> "period"
            else -> a.text
        }
        KeyAction.Shift -> when (state.shift) {
            Shift.OFF -> "shift"
            Shift.ONCE -> "shift on"
            Shift.LOCK -> "caps lock"
        }
        KeyAction.Backspace -> "delete"
        KeyAction.Return -> state.returnKind.label
        KeyAction.Page -> if (state.page == KeyPage.LETTERS) "numbers and symbols" else "letters"
        KeyAction.Symbols -> if (state.page == KeyPage.NUMBERS) "more symbols" else "numbers"
        KeyAction.Mode -> if (state.mode == "EN") "English mode" else "Khmer mode"
        KeyAction.Space -> "space"
    }

    private var a11yFocused = NO_ID
    private var hovered = NO_ID

    private val provider = object : AccessibilityNodeProvider() {
        @Suppress("DEPRECATION")
        override fun createAccessibilityNodeInfo(virtualViewId: Int): AccessibilityNodeInfo? {
            val host = this@KeyboardView
            val ts = targets()
            if (virtualViewId == AccessibilityNodeProvider.HOST_VIEW_ID) {
                val info = AccessibilityNodeInfo.obtain(host)
                onInitializeAccessibilityNodeInfo(info)
                info.contentDescription = "Typer keyboard"
                for (t in ts) info.addChild(host, t.id)
                return info
            }
            val t = ts.firstOrNull { it.id == virtualViewId } ?: return null
            val info = AccessibilityNodeInfo.obtain(host, t.id)
            info.packageName = context.packageName
            info.className = if (t.key) KEY_CLASS else BUTTON_CLASS
            info.contentDescription = t.label
            info.setParent(host)
            val r = Rect(px(t.box.left).toInt(), px(t.box.top).toInt(), px(t.box.right).toInt(), px(t.box.bottom).toInt())
            info.setBoundsInParent(r)
            val loc = IntArray(2)
            getLocationOnScreen(loc)
            r.offset(loc[0], loc[1])
            info.setBoundsInScreen(r)
            info.isEnabled = true
            info.isClickable = true
            info.isVisibleToUser = true
            info.isAccessibilityFocused = a11yFocused == t.id
            info.addAction(AccessibilityNodeInfo.AccessibilityAction.ACTION_CLICK)
            info.addAction(
                if (a11yFocused == t.id) AccessibilityNodeInfo.AccessibilityAction.ACTION_CLEAR_ACCESSIBILITY_FOCUS
                else AccessibilityNodeInfo.AccessibilityAction.ACTION_ACCESSIBILITY_FOCUS
            )
            return info
        }

        override fun performAction(virtualViewId: Int, action: Int, arguments: Bundle?): Boolean {
            if (virtualViewId == AccessibilityNodeProvider.HOST_VIEW_ID) return performAccessibilityAction(action, arguments)
            val t = targets().firstOrNull { it.id == virtualViewId } ?: return false
            return when (action) {
                AccessibilityNodeInfo.ACTION_CLICK -> {
                    t.activate()
                    send(t.id, AccessibilityEvent.TYPE_VIEW_CLICKED)
                    true
                }
                AccessibilityNodeInfo.ACTION_ACCESSIBILITY_FOCUS -> {
                    a11yFocused = t.id
                    send(t.id, AccessibilityEvent.TYPE_VIEW_ACCESSIBILITY_FOCUSED)
                    true
                }
                AccessibilityNodeInfo.ACTION_CLEAR_ACCESSIBILITY_FOCUS -> {
                    if (a11yFocused == t.id) a11yFocused = NO_ID
                    send(t.id, AccessibilityEvent.TYPE_VIEW_ACCESSIBILITY_FOCUS_CLEARED)
                    true
                }
                else -> false
            }
        }
    }

    override fun getAccessibilityNodeProvider(): AccessibilityNodeProvider = provider

    @Suppress("DEPRECATION")
    private fun send(id: Int, type: Int) {
        val am = context.getSystemService(Context.ACCESSIBILITY_SERVICE) as AccessibilityManager
        if (!am.isEnabled) return
        val e = AccessibilityEvent.obtain(type)
        e.packageName = context.packageName
        val t = targets().firstOrNull { it.id == id }
        e.className = if (t?.key == true) KEY_CLASS else BUTTON_CLASS
        e.setSource(this, id)
        t?.let { e.contentDescription = it.label }
        parent?.requestSendAccessibilityEvent(this, e)
    }

    /** Explore by touch (TalkBack): announce what is under the finger, type it when the finger lifts. */
    override fun dispatchHoverEvent(event: MotionEvent): Boolean {
        val am = context.getSystemService(Context.ACCESSIBILITY_SERVICE) as AccessibilityManager
        if (!am.isTouchExplorationEnabled) return super.dispatchHoverEvent(event)
        val x = event.x / d
        val y = event.y / d
        val ts = targets()
        val under = if (y < metrics.rowsTop || state.panelOpen) ts.firstOrNull { it.box.contains(x, y) }
        else KeyLayout.hit(x, y, keys)?.let { k -> ts.firstOrNull { it.id == KEYS + keys.indexOf(k) } }
        when (event.actionMasked) {
            MotionEvent.ACTION_HOVER_ENTER, MotionEvent.ACTION_HOVER_MOVE -> if (under?.id != hovered) {
                if (hovered != NO_ID) send(hovered, AccessibilityEvent.TYPE_VIEW_HOVER_EXIT)
                hovered = under?.id ?: NO_ID
                if (under != null) send(under.id, AccessibilityEvent.TYPE_VIEW_HOVER_ENTER)
            }
            MotionEvent.ACTION_HOVER_EXIT -> {
                ts.firstOrNull { it.id == hovered }?.let {
                    send(it.id, AccessibilityEvent.TYPE_VIEW_HOVER_EXIT)
                    it.activate()  // lift to type
                }
                hovered = NO_ID
            }
        }
        return true
    }

    companion object {
        /** reference.md: AOSP LatinIME defaults; Gboard's own long-press setting is 300 ms. */
        const val REPEAT_START = 400L
        const val REPEAT_INTERVAL = 50L
        const val LONG_PRESS = 300L
        private const val KEYS = 1
        private const val STRIP = 1000
        private const val PANEL = 2000
        private const val NO_ID = Int.MIN_VALUE
        /** The platform's keyboard-key class: screen readers treat it as a key and don't append "Button". */
        private const val KEY_CLASS = "android.inputmethodservice.Keyboard\$Key"
        private const val BUTTON_CLASS = "android.widget.Button"
    }
}
