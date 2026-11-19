# Sample set built from Karoryfer "Big Rusty Drums" (CC0).
# group -> (folder, file prefix, source velocity layers, layers to keep, round robins, {mic: weight}, max seconds)
# Mono close mics are panned to where the instrument sits in the overheads.
SPEC = {
 "kick":        ("kick_24/kick",      "k",          14, 7, 4, {"kick": 1.0, "oh": 0.40, "sn": 0.12}, 1.2),
 "snare":       ("snare_14/center",   "sn_center",  10, 7, 4, {"top": 1.0, "btm": 0.32, "oh": 0.55}, 1.3),
 "snare_rim":   ("snare_14/rimshot",  "sn_rims",     6, 5, 4, {"top": 1.0, "btm": 0.28, "oh": 0.55}, 1.4),
 "snare_brush": ("snare_14/brush",    "sn_b",        8, 5, 4, {"top": 1.0, "btm": 0.28, "oh": 0.70}, 1.2),
 "sidestick":   ("snare_14/sidestick","sn_ss",       4, 4, 4, {"top": 1.0, "oh": 0.50}, 0.8),
 "hat_closed":  ("hihat_14/tc",       "ht_tc",       8, 7, 4, {"cl": 1.0, "oh": 0.60}, 0.9),
 "hat_loose":   ("hihat_14/lc",       "ht_lc",       6, 4, 4, {"cl": 1.0, "oh": 0.65}, 1.2),
 "hat_open":    ("hihat_14/open",     "ht_open",     6, 4, 4, {"cl": 1.0, "oh": 0.70}, 1.8),
 "hat_pedal":   ("hihat_14/chik",     "ht_chik",     5, 3, 4, {"cl": 1.0, "oh": 0.60}, 0.6),
 "hat_brush":   ("hihat_14/tc_brush", "ht_tc_b",     5, 4, 4, {"cl": 1.0, "oh": 0.70}, 0.9),
 "ride":        ("ride_22/rd",        "rd",         10, 6, 3, {"cl": 0.6, "oh": 1.0}, 3.2),
 "ride_bell":   ("ride_22/bl",        "rd_bl",       4, 3, 4, {"cl": 0.6, "oh": 1.0}, 3.0),
 "crash":       ("crash_17/cr",       "cr",          5, 4, 4, {"cl": 0.5, "oh": 1.0}, 4.0),
 "tom_hi":      ("tom_14/center",     "t14",         6, 5, 4, {"cl": 1.0, "oh": 0.55, "sn": 0.10}, 1.6),
 "tom_mid":     ("tom_15/center",     "t15",         7, 5, 4, {"cl": 1.0, "oh": 0.55, "sn": 0.10}, 1.7),
 "tom_lo":      ("tom_18/center",     "t18",         8, 5, 4, {"cl": 1.0, "oh": 0.55, "sn": 0.10}, 1.9),
}


def layers(n, keep):
    """Spread `keep` layers over 1…n, always including the loudest."""
    if keep >= n:
        return list(range(1, n + 1))
    picks = sorted(set(round(1 + (n - 1) * (i / (keep - 1)) ** 0.9) for i in range(keep)))
    return picks
