# group name -> (folder, file prefix, layers N, {mic: weight}, stereo)
SPEC = {
 "kick":        ("kick_24/kick",     "k",          14, {"kick": 1.0, "oh": 0.45}),
 "snare":       ("snare_14/center",  "sn_center",  10, {"top": 1.0, "btm": 0.35, "oh": 0.55}),
 "snare_rim":   ("snare_14/rimshot", "sn_rims",     6, {"top": 1.0, "btm": 0.3, "oh": 0.55}),
 "snare_brush": ("snare_14/brush",   "sn_b",        8, {"top": 1.0, "btm": 0.3, "oh": 0.7}),
 "sidestick":   ("snare_14/sidestick","sn_ss",      4, {"top": 1.0, "oh": 0.5}),
 "hat_closed":  ("hihat_14/tc",      "ht_tc",       8, {"cl": 1.0, "oh": 0.6}),
 "hat_open":    ("hihat_14/open",    "ht_open",     6, {"cl": 1.0, "oh": 0.7}),
 "hat_brush":   ("hihat_14/tc_brush","ht_tc_b",     5, {"cl": 1.0, "oh": 0.7}),
 "ride":        ("ride_22/rd",       "rd",         10, {"cl": 0.6, "oh": 1.0}),
 "crash":       ("crash_17/cr",      "cr",          5, {"cl": 0.5, "oh": 1.0}),
 "tom_hi":      ("tom_14/center",    "t14",         6, {"cl": 1.0, "oh": 0.55}),
 "tom_lo":      ("tom_18/center",    "t18",         8, {"cl": 1.0, "oh": 0.55}),
}
def layers(n):
    a = sorted(set([max(1, round(n * 0.4)), max(1, round(n * 0.7)), n]))
    while len(a) < 3: a.insert(0, a[0])
    return a
