/* Typer for Linux: an IBus engine over the shared Rust engine (engine/typer.h).
 *
 * Same keys as macOS / Windows: letters and spaces build a latin phrase (the preedit);
 * IBus's own candidate window lists Khmer. Up/Down: move. Enter / 1-9 / click: insert.
 * ↓/↑ or Tab/Shift+Tab: move highlight. Esc: insert the latin as typed. Backspace: edit.
 * Punctuation joins the phrase as typed. Shortcuts: insert top suggestion, then the key goes on to the app.
 * Tap Ctrl alone with nothing typed: toggle English passthrough.
 */
#include <ibus.h>
#include "typer.h"

#ifndef TYPER_DATADIR
#define TYPER_DATADIR "/usr/share/typer"
#endif
#define TYPER_SETTINGS "/usr/lib/ibus-typer/typer-settings"

typedef struct {
    IBusEngine parent;
    GString *buffer;
    IBusLookupTable *table;
    IBusProperty *mode;   /* "InputMode": GNOME's top bar shows its symbol as the indicator */
    IBusProperty *settings; /* "Settings…" in the top-bar menu: opens Typer Settings */
    IBusPropList *props;
    gboolean ctrl_alone; /* Ctrl pressed with no other key since */
} TyperEngine;

typedef struct {
    IBusEngineClass parent;
} TyperEngineClass;

G_DEFINE_TYPE(TyperEngine, typer_engine, IBUS_TYPE_ENGINE)

static Engine *core;      /* one per process, shared by every input context */
static gboolean english;  /* shared by all apps, like Caps Lock */

static void typer_engine_init(TyperEngine *e) {
    if (!core) {
        gchar *user = g_build_filename(g_get_user_data_dir(), "typer", NULL); /* user.tsv + picks.tsv */
        core = typer_new(TYPER_DATADIR, user);
        g_free(user);
    }
    e->buffer = g_string_new(NULL);
    e->table = g_object_ref_sink(ibus_lookup_table_new(9, 0, TRUE, TRUE));
    ibus_lookup_table_set_orientation(e->table, IBUS_ORIENTATION_VERTICAL);
    e->mode = g_object_ref_sink(ibus_property_new("InputMode", PROP_TYPE_NORMAL, ibus_text_new_from_static_string("Typer"),
                                                  NULL, NULL, TRUE, TRUE, PROP_STATE_UNCHECKED, NULL));
    e->settings = g_object_ref_sink(ibus_property_new("settings", PROP_TYPE_NORMAL,
                                                      ibus_text_new_from_static_string("Typer Settings…"), NULL, NULL,
                                                      TRUE, TRUE, PROP_STATE_UNCHECKED, NULL));
    e->props = g_object_ref_sink(ibus_prop_list_new());
    ibus_prop_list_append(e->props, e->mode);
    ibus_prop_list_append(e->props, e->settings);
}

static void typer_engine_destroy(IBusObject *o) {
    TyperEngine *e = (TyperEngine *)o;
    if (e->buffer) {
        g_string_free(e->buffer, TRUE);
        e->buffer = NULL;
    }
    g_clear_object(&e->table);
    g_clear_object(&e->props);
    g_clear_object(&e->mode);
    g_clear_object(&e->settings);
    IBUS_OBJECT_CLASS(typer_engine_parent_class)->destroy(o);
}

static void show_mode(TyperEngine *e);

/* Show the buffer as underlined preedit and refresh the candidates under it. */
static void update(TyperEngine *e) {
    IBusEngine *ie = (IBusEngine *)e;
    show_mode(e);
    ibus_lookup_table_clear(e->table);
    if (e->buffer->len == 0) {
        ibus_engine_hide_preedit_text(ie);
        ibus_engine_hide_lookup_table(ie);
        return;
    }
    IBusText *pre = ibus_text_new_from_string(e->buffer->str);
    ibus_text_append_attribute(pre, IBUS_ATTR_TYPE_UNDERLINE, IBUS_ATTR_UNDERLINE_SINGLE, 0, e->buffer->len);
    ibus_engine_update_preedit_text(ie, pre, e->buffer->len, TRUE); /* buffer is ASCII: bytes == chars */

    gchar *trimmed = g_strstrip(g_strdup(e->buffer->str));
    char *s = (*trimmed && core) ? typer_suggest(core, e->buffer->str, 9) : NULL;
    g_free(trimmed);
    if (s) {
        gchar **lines = g_strsplit(s, "\n", -1);
        for (gchar **l = lines; *l; l++)
            if (**l) ibus_lookup_table_append_candidate(e->table, ibus_text_new_from_string(*l));
        g_strfreev(lines);
        typer_string_free(s);
    }
    ibus_engine_update_lookup_table(ie, e->table, ibus_lookup_table_get_number_of_candidates(e->table) > 0);
}

/* Replace the preedit with `text` and start over. */
static void finish(TyperEngine *e, const gchar *text) {
    IBusEngine *ie = (IBusEngine *)e;
    ibus_engine_hide_preedit_text(ie);
    ibus_engine_hide_lookup_table(ie);
    if (*text) ibus_engine_commit_text(ie, ibus_text_new_from_string(text));
    g_string_truncate(e->buffer, 0);
    ibus_lookup_table_clear(e->table);
    show_mode(e);
}

/* Insert candidate `i` (or the latin if there is none) and learn the pick. */
static void commit(TyperEngine *e, guint i) {
    gchar *input = g_strdup(e->buffer->str);
    IBusText *c = ibus_lookup_table_get_candidate(e->table, i);
    gchar *text = g_strdup(c ? ibus_text_get_text(c) : input);
    finish(e, text);
    if (c && core) typer_pick(core, input, i);
    g_free(text);
    g_free(input);
}

static void commit_latin(TyperEngine *e) {
    gchar *raw = g_strdup(e->buffer->str);
    finish(e, raw);
    g_free(raw);
}

/* Persistent mode indicator: "EN" / "ខ" in the popup under the caret while idle
 * (the suggestion list has that spot while composing), and as the top-bar symbol. */
static void show_mode(TyperEngine *e) {
    IBusEngine *ie = (IBusEngine *)e;
    ibus_property_set_symbol(e->mode, ibus_text_new_from_static_string(english ? "EN" : "ខ"));
    ibus_property_set_label(e->mode, ibus_text_new_from_static_string(english ? "English" : "Khmer"));
    if (e->buffer->len || (core && !typer_setting(core, "badge")))
        ibus_engine_hide_auxiliary_text(ie);
    else
        ibus_engine_update_auxiliary_text(ie, ibus_text_new_from_static_string(english ? "EN" : "ខ"), TRUE);
}

static void focus_in(IBusEngine *ie) {
    TyperEngine *e = (TyperEngine *)ie;
    show_mode(e); /* english is shared: another app may have toggled it */
    ibus_engine_register_properties(ie, e->props);
}

/* Mirrors macos/InputController.swift. TRUE = we handled the key. */
static gboolean process_key_event(IBusEngine *ie, guint keyval, guint keycode, guint mods) {
    TyperEngine *e = (TyperEngine *)ie;
    (void)keycode;
    gboolean ctrl_key = keyval == IBUS_KEY_Control_L || keyval == IBUS_KEY_Control_R;
    if (mods & IBUS_RELEASE_MASK) {
        if (ctrl_key && e->ctrl_alone && e->buffer->len == 0) {
            english = !english;
            show_mode(e);
            ibus_engine_update_property(ie, e->mode);
        }
        if (ctrl_key) e->ctrl_alone = FALSE;
        return FALSE;
    }
    e->ctrl_alone = ctrl_key; /* any other key: Ctrl was a modifier, not a tap */
    if (ctrl_key || keyval == IBUS_KEY_Shift_L || keyval == IBUS_KEY_Shift_R || english) return FALSE;

    gboolean composing = e->buffer->len > 0;
    guint n = ibus_lookup_table_get_number_of_candidates(e->table);
    if (mods & (IBUS_CONTROL_MASK | IBUS_MOD1_MASK | IBUS_SUPER_MASK | IBUS_META_MASK | IBUS_MOD4_MASK)) {
        if (composing) commit(e, 0);
        return FALSE;
    }
    if (composing) {
        switch (keyval) {
        case IBUS_KEY_Return:
        case IBUS_KEY_KP_Enter:
            commit(e, ibus_lookup_table_get_cursor_pos(e->table));
            return TRUE;
        case IBUS_KEY_Tab:
        case IBUS_KEY_ISO_Left_Tab: /* Shift+Tab */
            if (!n) break;          /* no suggestions: an ordinary key */
            /* fall through */
        case IBUS_KEY_Down:
        case IBUS_KEY_Up:
            if (n) {
                if (keyval == IBUS_KEY_Up || keyval == IBUS_KEY_ISO_Left_Tab)
                    ibus_lookup_table_cursor_up(e->table);
                else
                    ibus_lookup_table_cursor_down(e->table);
                ibus_engine_update_lookup_table(ie, e->table, TRUE);
            }
            return TRUE;
        case IBUS_KEY_Escape:
            commit_latin(e);
            return TRUE;
        case IBUS_KEY_BackSpace:
            g_string_truncate(e->buffer, e->buffer->len - 1);
            update(e);
            return TRUE;
        }
    }
    if ((keyval >= 'a' && keyval <= 'z') || (keyval >= 'A' && keyval <= 'Z') || keyval == IBUS_KEY_apostrophe) {
        g_string_append_c(e->buffer, (gchar)keyval);
        update(e);
        return TRUE;
    }
    if (composing && keyval == IBUS_KEY_space) {
        if (e->buffer->str[e->buffer->len - 1] != ' ') g_string_append_c(e->buffer, ' '); /* separates words */
        update(e);
        return TRUE;
    }
    if (composing && keyval >= '1' && keyval <= '9' && keyval - '1' < n) {
        commit(e, keyval - '1');
        return TRUE;
    }
    if (composing && keyval < 0x80 && g_ascii_ispunct((gchar)keyval)) {
        g_string_append_c(e->buffer, (gchar)keyval); /* stays as typed in the suggestion */
        update(e);
        return TRUE;
    }
    if (composing) commit(e, 0);
    return FALSE;
}

static void property_activate(IBusEngine *ie, const gchar *name, guint state) {
    (void)ie;
    (void)state;
    if (g_strcmp0(name, "settings") == 0) g_spawn_command_line_async(TYPER_SETTINGS, NULL);
}

static void candidate_clicked(IBusEngine *ie, guint index, guint button, guint state) {
    (void)button;
    (void)state;
    commit((TyperEngine *)ie, index);
}

/* Focus moved away mid-phrase: keep what was typed, don't guess. */
static void keep_latin(IBusEngine *ie) {
    TyperEngine *e = (TyperEngine *)ie;
    if (e->buffer->len) commit_latin(e);
}

static void typer_engine_class_init(TyperEngineClass *klass) {
    IBUS_OBJECT_CLASS(klass)->destroy = typer_engine_destroy;
    IBusEngineClass *ec = IBUS_ENGINE_CLASS(klass);
    ec->process_key_event = process_key_event;
    ec->candidate_clicked = candidate_clicked;
    ec->property_activate = property_activate;
    ec->focus_in = focus_in;
    ec->enable = focus_in;
    ec->focus_out = keep_latin;
    ec->reset = keep_latin;
    ec->disable = keep_latin;
}

static void quit(IBusBus *bus, gpointer data) {
    (void)bus;
    (void)data;
    ibus_quit();
}

/* Started by ibus-daemon (see typer.xml) with --ibus. */
int main(void) {
    ibus_init();
    IBusBus *bus = ibus_bus_new();
    if (!ibus_bus_is_connected(bus)) {
        g_printerr("ibus-engine-typer: cannot connect to ibus-daemon\n");
        return 1;
    }
    g_signal_connect(bus, "disconnected", G_CALLBACK(quit), NULL);
    IBusFactory *factory = ibus_factory_new(ibus_bus_get_connection(bus));
    ibus_factory_add_engine(factory, "typer", typer_engine_get_type());
    ibus_bus_request_name(bus, "org.freedesktop.IBus.Typer", 0);
    ibus_main();
    return 0;
}
