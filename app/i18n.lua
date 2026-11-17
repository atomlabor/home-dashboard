-- English first, German as the alternative.
local M = {}

M.en = {
  title = "Home",
  nav = { "Home", "Music", "Sensors", "Settings" },
  music = "Music", now_playing = "Now playing", nothing_playing = "Nothing is playing right now.",
  paused = "Paused", player_of = "Player %d of %d",
  live = "Live", offline = "Offline", connecting = "Connecting\u{2026}",
  loading = "Loading\u{2026}",
  asof = "as of %s",
  err_short = "Not connected",
  err_auth = "Home Assistant rejected the sign-in.",
  err_other = "Home Assistant not reachable",
  err_busy = "Busy, please try again.",
  err_mfa = "This account uses two-factor sign-in. Use a token instead.",
  err_invalid = "User name or password is wrong.",
  err_banned = "Too many attempts. Wait a moment and try again.",
  err_file = "No homeassistant.txt with a token found.",
  empty = "Nothing to show yet.",
  on = "On", off = "Off", na = "n/a",
  lights = "Lights & switches", lights_on = "%d on",
  sensors = "All sensors",
  -- setup
  setup_title = "Connect Home Assistant",
  setup_text = "Sign in once with your Home Assistant user. The device keeps only a sign-in key, never your password.",
  f_server = "Server address",
  b_login = "Sign in with user name",
  b_token = "Paste access token",
  b_file = "Read homeassistant.txt",
  file_hint = "Or put homeassistant.txt (url = \u{2026} / token = \u{2026}) into %s",
  file_hint_nopath = "Or put homeassistant.txt (url = \u{2026} / token = \u{2026}) into the app folder",
  ask_url = "Home Assistant address", ask_user = "User name", ask_pass = "Password",
  ask_token = "Long-lived access token",
  connected = "Connected",
  -- settings
  g_conn = "CONNECTION", g_lock = "LOCK SCREEN", g_general = "GENERAL",
  s_server = "Server", s_account = "Account", s_test = "Refresh now",
  acc_login = "Signed in as %s", acc_login_anon = "Signed in", acc_token = "Access token",
  acc_file = "From homeassistant.txt", acc_install = "From install settings", acc_none = "Not connected",
  s_logout = "Sign out",
  use_lock = "Use as lock screen",
  s_pins = "Values on the lock screen", pins_count = "%d of %d",
  pins_title = "Lock screen values",
  pins_auto = "Nothing chosen: the lock screen picks values itself.",
  max_pins = "At most %d values on the lock screen",
  lang = "Language", lang_name = "English",
  version = "Version",
  g_display = "DISPLAY", s_visible = "Dashboard items", vis_title = "Customize dashboard",
  vis_count = "%d of %d shown", all_on = "Show all", all_off = "Hide all",
  -- lock screen
  lock_on = "Lights on",
  lock_none = "All lights off",
  lock_more = "+%d more",
  lock_home = "HOME",
  wd = { "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday" },
  mon = { "January", "February", "March", "April", "May", "June", "July", "August",
    "September", "October", "November", "December" },
  date = function(wd, d, mon) return wd .. ", " .. mon .. " " .. d end,
  comma = false,
}

M.de = {
  title = "Zuhause",
  nav = { "\u{00DC}bersicht", "Musik", "Sensoren", "Einstellungen" },
  music = "Musik", now_playing = "L\u{00E4}uft gerade", nothing_playing = "Gerade l\u{00E4}uft nichts.",
  paused = "Pausiert", player_of = "Player %d von %d",
  live = "Live", offline = "Offline", connecting = "Verbinde\u{2026}",
  loading = "L\u{00E4}dt\u{2026}",
  asof = "Stand %s",
  err_short = "Nicht verbunden",
  err_auth = "Home Assistant hat die Anmeldung abgelehnt.",
  err_other = "Home Assistant nicht erreichbar",
  err_busy = "Gerade besch\u{00E4}ftigt, bitte noch einmal.",
  err_mfa = "Das Konto nutzt Zwei-Faktor-Anmeldung. Bitte ein Token verwenden.",
  err_invalid = "Benutzername oder Passwort stimmt nicht.",
  err_banned = "Zu viele Versuche. Kurz warten und erneut probieren.",
  err_file = "Keine homeassistant.txt mit Token gefunden.",
  empty = "Noch nichts zu zeigen.",
  on = "An", off = "Aus", na = "k. A.",
  lights = "Licht & Schalter", lights_on = "%d an",
  sensors = "Alle Sensoren",
  setup_title = "Home Assistant verbinden",
  setup_text = "Melde dich einmal mit deinem Home-Assistant-Benutzer an. Das Ger\u{00E4}t beh\u{00E4}lt nur einen Anmeldeschl\u{00FC}ssel, nie dein Passwort.",
  f_server = "Serveradresse",
  b_login = "Mit Benutzername anmelden",
  b_token = "Zugriffstoken einf\u{00FC}gen",
  b_file = "homeassistant.txt einlesen",
  file_hint = "Oder homeassistant.txt (url = \u{2026} / token = \u{2026}) ablegen in %s",
  file_hint_nopath = "Oder homeassistant.txt (url = \u{2026} / token = \u{2026}) in den App-Ordner legen",
  ask_url = "Adresse von Home Assistant", ask_user = "Benutzername", ask_pass = "Passwort",
  ask_token = "Langzeit-Zugriffstoken",
  connected = "Verbunden",
  g_conn = "VERBINDUNG", g_lock = "SPERRBILDSCHIRM", g_general = "ALLGEMEIN",
  s_server = "Server", s_account = "Konto", s_test = "Jetzt aktualisieren",
  acc_login = "Angemeldet als %s", acc_login_anon = "Angemeldet", acc_token = "Zugriffstoken",
  acc_file = "Aus homeassistant.txt", acc_install = "Aus Installation", acc_none = "Nicht verbunden",
  s_logout = "Abmelden",
  use_lock = "Als Sperrbildschirm nutzen",
  s_pins = "Werte auf dem Sperrbildschirm", pins_count = "%d von %d",
  pins_title = "Sperrbildschirm-Werte",
  pins_auto = "Nichts gew\u{00E4}hlt: der Sperrbildschirm w\u{00E4}hlt selbst.",
  max_pins = "H\u{00F6}chstens %d Werte auf dem Sperrbildschirm",
  lang = "Sprache", lang_name = "Deutsch",
  version = "Version",
  g_display = "ANZEIGE", s_visible = "Dashboard-Inhalte", vis_title = "Dashboard anpassen",
  vis_count = "%d von %d sichtbar", all_on = "Alle anzeigen", all_off = "Alle ausblenden",
  lock_on = "Licht an",
  lock_none = "Alle Lichter aus",
  lock_more = "+%d weitere",
  lock_home = "ZUHAUSE",
  wd = { "Sonntag", "Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag" },
  mon = { "Januar", "Februar", "M\u{00E4}rz", "April", "Mai", "Juni", "Juli", "August",
    "September", "Oktober", "November", "Dezember" },
  date = function(wd, d, mon) return wd .. ", " .. d .. ". " .. mon end,
  comma = true,
}

function M.get(lang) return M[lang] or M.en end

function M.error(T, e)
  if e == "auth" then return T.err_auth end
  if e == "busy" then return T.err_busy end
  if e == "mfa" then return T.err_mfa end
  if e == "invalid_auth" then return T.err_invalid end
  if e == "banned" then return T.err_banned end
  if e == "config" then return T.err_short end
  if e == "file" then return T.err_file end
  return T.err_other
end

return M
