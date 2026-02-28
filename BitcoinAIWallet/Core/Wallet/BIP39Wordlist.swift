import Foundation

// MARK: - BIP39 English Wordlist
// Complete list of 2048 words per BIP39 specification (BIP-0039)
// Reference: https://github.com/bitcoin/bips/blob/master/bip-0039/english.txt
// Each word is uniquely identifiable by its first 4 characters.

enum BIP39Wordlist {

    // MARK: - Complete English Wordlist (2048 words)

    static let english: [String] = [
        "abandon", "ability", "able", "about", "above", "absent", "absorb", "abstract",  // 0-7
        "absurd", "abuse", "access", "accident", "account", "accuse", "achieve", "acid",  // 8-15
        "acoustic", "acquire", "across", "act", "action", "actor", "actress", "actual",  // 16-23
        "adapt", "add", "addict", "address", "adjust", "admit", "adult", "advance",  // 24-31
        "advice", "aerobic", "affair", "afford", "afraid", "again", "age", "agent",  // 32-39
        "agree", "ahead", "aim", "air", "airport", "aisle", "alarm", "album",  // 40-47
        "alcohol", "alert", "alien", "all", "alley", "allow", "almost", "alone",  // 48-55
        "alpha", "already", "also", "alter", "always", "amateur", "amazing", "among",  // 56-63
        "amount", "amused", "analyst", "anchor", "ancient", "anger", "angle", "angry",  // 64-71
        "animal", "ankle", "announce", "annual", "another", "answer", "antenna", "antique",  // 72-79
        "anxiety", "any", "apart", "apology", "appear", "apple", "approve", "april",  // 80-87
        "arch", "arctic", "area", "arena", "argue", "arm", "armed", "armor",  // 88-95
        "army", "around", "arrange", "arrest", "arrive", "arrow", "art", "artefact",  // 96-103
        "artist", "artwork", "ask", "aspect", "assault", "asset", "assist", "assume",  // 104-111
        "asthma", "athlete", "atom", "attack", "attend", "attitude", "attract", "auction",  // 112-119
        "audit", "august", "aunt", "author", "auto", "autumn", "average", "avocado",  // 120-127
        "avoid", "awake", "aware", "away", "awesome", "awful", "awkward", "axis",  // 128-135
        "baby", "bachelor", "bacon", "badge", "bag", "balance", "balcony", "ball",  // 136-143
        "bamboo", "banana", "banner", "bar", "barely", "bargain", "barrel", "base",  // 144-151
        "basic", "basket", "battle", "beach", "bean", "beauty", "because", "become",  // 152-159
        "beef", "before", "begin", "behave", "behind", "believe", "below", "belt",  // 160-167
        "bench", "benefit", "best", "betray", "better", "between", "beyond", "bicycle",  // 168-175
        "bid", "bike", "bind", "biology", "bird", "birth", "bitter", "black",  // 176-183
        "blade", "blame", "blanket", "blast", "bleak", "bless", "blind", "blood",  // 184-191
        "blossom", "blouse", "blue", "blur", "blush", "board", "boat", "body",  // 192-199
        "boil", "bomb", "bone", "bonus", "book", "boost", "border", "boring",  // 200-207
        "borrow", "boss", "bottom", "bounce", "box", "boy", "bracket", "brain",  // 208-215
        "brand", "brass", "brave", "bread", "breeze", "brick", "bridge", "brief",  // 216-223
        "bright", "bring", "brisk", "broccoli", "broken", "bronze", "broom", "brother",  // 224-231
        "brown", "brush", "bubble", "buddy", "budget", "buffalo", "build", "bulb",  // 232-239
        "bulk", "bullet", "bundle", "bunker", "burden", "burger", "burst", "bus",  // 240-247
        "business", "busy", "butter", "buyer", "buzz", "cabbage", "cabin", "cable",  // 248-255
        "cactus", "cage", "cake", "call", "calm", "camera", "camp", "can",  // 256-263
        "canal", "cancel", "candy", "cannon", "canoe", "canvas", "canyon", "capable",  // 264-271
        "capital", "captain", "car", "carbon", "card", "cargo", "carpet", "carry",  // 272-279
        "cart", "case", "cash", "casino", "castle", "casual", "cat", "catalog",  // 280-287
        "catch", "category", "cattle", "caught", "cause", "caution", "cave", "ceiling",  // 288-295
        "celery", "cement", "census", "century", "cereal", "certain", "chair", "chalk",  // 296-303
        "champion", "change", "chaos", "chapter", "charge", "chase", "chat", "cheap",  // 304-311
        "check", "cheese", "chef", "cherry", "chest", "chicken", "chief", "child",  // 312-319
        "chimney", "choice", "choose", "chronic", "chuckle", "chunk", "churn", "cigar",  // 320-327
        "cinnamon", "circle", "citizen", "city", "civil", "claim", "clap", "clarify",  // 328-335
        "claw", "clay", "clean", "clerk", "clever", "click", "client", "cliff",  // 336-343
        "climb", "clinic", "clip", "clock", "clog", "close", "cloth", "cloud",  // 344-351
        "clown", "club", "clump", "cluster", "clutch", "coach", "coast", "coconut",  // 352-359
        "code", "coffee", "coil", "coin", "collect", "color", "column", "combine",  // 360-367
        "come", "comfort", "comic", "common", "company", "concert", "conduct", "confirm",  // 368-375
        "congress", "connect", "consider", "control", "convince", "cook", "cool", "copper",  // 376-383
        "copy", "coral", "core", "corn", "correct", "cost", "cotton", "couch",  // 384-391
        "country", "couple", "course", "cousin", "cover", "coyote", "crack", "cradle",  // 392-399
        "craft", "cram", "crane", "crash", "crater", "crawl", "crazy", "cream",  // 400-407
        "credit", "creek", "crew", "cricket", "crime", "crisp", "critic", "crop",  // 408-415
        "cross", "crouch", "crowd", "crucial", "cruel", "cruise", "crumble", "crunch",  // 416-423
        "crush", "cry", "crystal", "cube", "culture", "cup", "cupboard", "curious",  // 424-431
        "current", "curtain", "curve", "cushion", "custom", "cute", "cycle", "dad",  // 432-439
        "damage", "damp", "dance", "danger", "daring", "dash", "daughter", "dawn",  // 440-447
        "day", "deal", "debate", "debris", "decade", "december", "decide", "decline",  // 448-455
        "decorate", "decrease", "deer", "defense", "define", "defy", "degree", "delay",  // 456-463
        "deliver", "demand", "demise", "denial", "dentist", "deny", "depart", "depend",  // 464-471
        "deposit", "depth", "deputy", "derive", "describe", "desert", "design", "desk",  // 472-479
        "despair", "destroy", "detail", "detect", "develop", "device", "devote", "diagram",  // 480-487
        "dial", "diamond", "diary", "dice", "diesel", "diet", "differ", "digital",  // 488-495
        "dignity", "dilemma", "dinner", "dinosaur", "direct", "dirt", "disagree", "discover",  // 496-503
        "disease", "dish", "dismiss", "disorder", "display", "distance", "divert", "divide",  // 504-511
        "divorce", "dizzy", "doctor", "document", "dog", "doll", "dolphin", "domain",  // 512-519
        "donate", "donkey", "donor", "door", "dose", "double", "dove", "draft",  // 520-527
        "dragon", "drama", "drastic", "draw", "dream", "dress", "drift", "drill",  // 528-535
        "drink", "drip", "drive", "drop", "drum", "dry", "duck", "dumb",  // 536-543
        "dune", "during", "dust", "dutch", "duty", "dwarf", "dynamic", "eager",  // 544-551
        "eagle", "early", "earn", "earth", "easily", "east", "easy", "echo",  // 552-559
        "ecology", "economy", "edge", "edit", "educate", "effort", "egg", "eight",  // 560-567
        "either", "elbow", "elder", "electric", "elegant", "element", "elephant", "elevator",  // 568-575
        "elite", "else", "embark", "embody", "embrace", "emerge", "emotion", "employ",  // 576-583
        "empower", "empty", "enable", "enact", "end", "endless", "endorse", "enemy",  // 584-591
        "energy", "enforce", "engage", "engine", "enhance", "enjoy", "enlist", "enough",  // 592-599
        "enrich", "enroll", "ensure", "enter", "entire", "entry", "envelope", "episode",  // 600-607
        "equal", "equip", "era", "erase", "erode", "erosion", "error", "erupt",  // 608-615
        "escape", "essay", "essence", "estate", "eternal", "ethics", "evidence", "evil",  // 616-623
        "evoke", "evolve", "exact", "example", "excess", "exchange", "excite", "exclude",  // 624-631
        "excuse", "execute", "exercise", "exhaust", "exhibit", "exile", "exist", "exit",  // 632-639
        "exotic", "expand", "expect", "expire", "explain", "expose", "express", "extend",  // 640-647
        "extra", "eye", "eyebrow", "fabric", "face", "faculty", "fade", "faint",  // 648-655
        "faith", "fall", "false", "fame", "family", "famous", "fan", "fancy",  // 656-663
        "fantasy", "farm", "fashion", "fat", "fatal", "father", "fatigue", "fault",  // 664-671
        "favorite", "feature", "february", "federal", "fee", "feed", "feel", "female",  // 672-679
        "fence", "festival", "fetch", "fever", "few", "fiber", "fiction", "field",  // 680-687
        "figure", "file", "film", "filter", "final", "find", "fine", "finger",  // 688-695
        "finish", "fire", "firm", "first", "fiscal", "fish", "fit", "fitness",  // 696-703
        "fix", "flag", "flame", "flash", "flat", "flavor", "flee", "flight",  // 704-711
        "flip", "float", "flock", "floor", "flower", "fluid", "flush", "fly",  // 712-719
        "foam", "focus", "fog", "foil", "fold", "follow", "food", "foot",  // 720-727
        "force", "forest", "forget", "fork", "fortune", "forum", "forward", "fossil",  // 728-735
        "foster", "found", "fox", "fragile", "frame", "frequent", "fresh", "friend",  // 736-743
        "fringe", "frog", "front", "frost", "frown", "frozen", "fruit", "fuel",  // 744-751
        "fun", "funny", "furnace", "fury", "future", "gadget", "gain", "galaxy",  // 752-759
        "gallery", "game", "gap", "garage", "garbage", "garden", "garlic", "garment",  // 760-767
        "gas", "gasp", "gate", "gather", "gauge", "gaze", "general", "genius",  // 768-775
        "genre", "gentle", "genuine", "gesture", "ghost", "giant", "gift", "giggle",  // 776-783
        "ginger", "giraffe", "girl", "give", "glad", "glance", "glare", "glass",  // 784-791
        "glide", "glimpse", "globe", "gloom", "glory", "glove", "glow", "glue",  // 792-799
        "goat", "goddess", "gold", "good", "goose", "gorilla", "gospel", "gossip",  // 800-807
        "govern", "gown", "grab", "grace", "grain", "grant", "grape", "grass",  // 808-815
        "gravity", "great", "green", "grid", "grief", "grit", "grocery", "group",  // 816-823
        "grow", "grunt", "guard", "guess", "guide", "guilt", "guitar", "gun",  // 824-831
        "gym", "habit", "hair", "half", "hammer", "hamster", "hand", "happy",  // 832-839
        "harbor", "hard", "harsh", "harvest", "hat", "have", "hawk", "hazard",  // 840-847
        "head", "health", "heart", "heavy", "hedgehog", "height", "hello", "helmet",  // 848-855
        "help", "hen", "hero", "hidden", "high", "hill", "hint", "hip",  // 856-863
        "hire", "history", "hobby", "hockey", "hold", "hole", "holiday", "hollow",  // 864-871
        "home", "honey", "hood", "hope", "horn", "horror", "horse", "hospital",  // 872-879
        "host", "hotel", "hour", "hover", "hub", "huge", "human", "humble",  // 880-887
        "humor", "hundred", "hungry", "hunt", "hurdle", "hurry", "hurt", "husband",  // 888-895
        "hybrid", "ice", "icon", "idea", "identify", "idle", "ignore", "ill",  // 896-903
        "illegal", "illness", "image", "imitate", "immense", "immune", "impact", "impose",  // 904-911
        "improve", "impulse", "inch", "include", "income", "increase", "index", "indicate",  // 912-919
        "indoor", "industry", "infant", "inflict", "inform", "inhale", "inherit", "initial",  // 920-927
        "inject", "injury", "inmate", "inner", "innocent", "input", "inquiry", "insane",  // 928-935
        "insect", "inside", "inspire", "install", "intact", "interest", "into", "invest",  // 936-943
        "invite", "involve", "iron", "island", "isolate", "issue", "item", "ivory",  // 944-951
        "jacket", "jaguar", "jar", "jazz", "jealous", "jeans", "jelly", "jewel",  // 952-959
        "job", "join", "joke", "journey", "joy", "judge", "juice", "jump",  // 960-967
        "jungle", "junior", "junk", "just", "kangaroo", "keen", "keep", "ketchup",  // 968-975
        "key", "kick", "kid", "kidney", "kind", "kingdom", "kiss", "kit",  // 976-983
        "kitchen", "kite", "kitten", "kiwi", "knee", "knife", "knock", "know",  // 984-991
        "lab", "label", "labor", "ladder", "lady", "lake", "lamp", "language",  // 992-999
        "laptop", "large", "later", "latin", "laugh", "laundry", "lava", "law",  // 1000-1007
        "lawn", "lawsuit", "layer", "lazy", "leader", "leaf", "learn", "leave",  // 1008-1015
        "lecture", "left", "leg", "legal", "legend", "leisure", "lemon", "lend",  // 1016-1023
        "length", "lens", "leopard", "lesson", "letter", "level", "liar", "liberty",  // 1024-1031
        "library", "license", "life", "lift", "light", "like", "limb", "limit",  // 1032-1039
        "link", "lion", "liquid", "list", "little", "live", "lizard", "load",  // 1040-1047
        "loan", "lobster", "local", "lock", "logic", "lonely", "long", "loop",  // 1048-1055
        "lottery", "loud", "lounge", "love", "loyal", "lucky", "luggage", "lumber",  // 1056-1063
        "lunar", "lunch", "luxury", "lyrics", "machine", "mad", "magic", "magnet",  // 1064-1071
        "maid", "mail", "main", "major", "make", "mammal", "man", "manage",  // 1072-1079
        "mandate", "mango", "mansion", "manual", "maple", "marble", "march", "margin",  // 1080-1087
        "marine", "market", "marriage", "mask", "mass", "master", "match", "material",  // 1088-1095
        "math", "matrix", "matter", "maximum", "maze", "meadow", "mean", "measure",  // 1096-1103
        "meat", "mechanic", "medal", "media", "melody", "melt", "member", "memory",  // 1104-1111
        "mention", "menu", "mercy", "merge", "merit", "merry", "mesh", "message",  // 1112-1119
        "metal", "method", "middle", "midnight", "milk", "million", "mimic", "mind",  // 1120-1127
        "minimum", "minor", "minute", "miracle", "mirror", "misery", "miss", "mistake",  // 1128-1135
        "mix", "mixed", "mixture", "mobile", "model", "modify", "mom", "moment",  // 1136-1143
        "monitor", "monkey", "monster", "month", "moon", "moral", "more", "morning",  // 1144-1151
        "mosquito", "mother", "motion", "motor", "mountain", "mouse", "move", "movie",  // 1152-1159
        "much", "muffin", "mule", "multiply", "muscle", "museum", "mushroom", "music",  // 1160-1167
        "must", "mutual", "myself", "mystery", "myth", "naive", "name", "napkin",  // 1168-1175
        "narrow", "nasty", "nation", "nature", "near", "neck", "need", "negative",  // 1176-1183
        "neglect", "neither", "nephew", "nerve", "nest", "net", "network", "neutral",  // 1184-1191
        "never", "news", "next", "nice", "night", "noble", "noise", "nominee",  // 1192-1199
        "noodle", "normal", "north", "nose", "notable", "note", "nothing", "notice",  // 1200-1207
        "novel", "now", "nuclear", "number", "nurse", "nut", "oak", "obey",  // 1208-1215
        "object", "oblige", "obscure", "observe", "obtain", "obvious", "occur", "ocean",  // 1216-1223
        "october", "odor", "off", "offer", "office", "often", "oil", "okay",  // 1224-1231
        "old", "olive", "olympic", "omit", "once", "one", "onion", "online",  // 1232-1239
        "only", "open", "opera", "opinion", "oppose", "option", "orange", "orbit",  // 1240-1247
        "orchard", "order", "ordinary", "organ", "orient", "original", "orphan", "ostrich",  // 1248-1255
        "other", "outdoor", "outer", "output", "outside", "oval", "oven", "over",  // 1256-1263
        "own", "owner", "oxygen", "oyster", "ozone", "pact", "paddle", "page",  // 1264-1271
        "pair", "palace", "palm", "panda", "panel", "panic", "panther", "paper",  // 1272-1279
        "parade", "parent", "park", "parrot", "party", "pass", "patch", "path",  // 1280-1287
        "patient", "patrol", "pattern", "pause", "pave", "payment", "peace", "peanut",  // 1288-1295
        "pear", "peasant", "pelican", "pen", "penalty", "pencil", "people", "pepper",  // 1296-1303
        "perfect", "permit", "person", "pet", "phone", "photo", "phrase", "physical",  // 1304-1311
        "piano", "picnic", "picture", "piece", "pig", "pigeon", "pill", "pilot",  // 1312-1319
        "pink", "pioneer", "pipe", "pistol", "pitch", "pizza", "place", "planet",  // 1320-1327
        "plastic", "plate", "play", "please", "pledge", "pluck", "plug", "plunge",  // 1328-1335
        "poem", "poet", "point", "polar", "pole", "police", "pond", "pony",  // 1336-1343
        "pool", "popular", "portion", "position", "possible", "post", "potato", "pottery",  // 1344-1351
        "poverty", "powder", "power", "practice", "praise", "predict", "prefer", "prepare",  // 1352-1359
        "present", "pretty", "prevent", "price", "pride", "primary", "print", "priority",  // 1360-1367
        "prison", "private", "prize", "problem", "process", "produce", "profit", "program",  // 1368-1375
        "project", "promote", "proof", "property", "prosper", "protect", "proud", "provide",  // 1376-1383
        "public", "pudding", "pull", "pulp", "pulse", "pumpkin", "punch", "pupil",  // 1384-1391
        "puppy", "purchase", "purity", "purpose", "purse", "push", "put", "puzzle",  // 1392-1399
        "pyramid", "quality", "quantum", "quarter", "question", "quick", "quit", "quiz",  // 1400-1407
        "quote", "rabbit", "raccoon", "race", "rack", "radar", "radio", "rail",  // 1408-1415
        "rain", "raise", "rally", "ramp", "ranch", "random", "range", "rapid",  // 1416-1423
        "rare", "rate", "rather", "raven", "raw", "razor", "ready", "real",  // 1424-1431
        "reason", "rebel", "rebuild", "recall", "receive", "recipe", "record", "recycle",  // 1432-1439
        "reduce", "reflect", "reform", "refuse", "region", "regret", "regular", "reject",  // 1440-1447
        "relax", "release", "relief", "rely", "remain", "remember", "remind", "remove",  // 1448-1455
        "render", "renew", "rent", "reopen", "repair", "repeat", "replace", "report",  // 1456-1463
        "require", "rescue", "resemble", "resist", "resource", "response", "result", "retire",  // 1464-1471
        "retreat", "return", "reunion", "reveal", "review", "reward", "rhythm", "rib",  // 1472-1479
        "ribbon", "rice", "rich", "ride", "ridge", "rifle", "right", "rigid",  // 1480-1487
        "ring", "riot", "ripple", "risk", "ritual", "rival", "river", "road",  // 1488-1495
        "roast", "robot", "robust", "rocket", "romance", "roof", "rookie", "room",  // 1496-1503
        "rose", "rotate", "rough", "round", "route", "royal", "rubber", "rude",  // 1504-1511
        "rug", "rule", "run", "runway", "rural", "sad", "saddle", "sadness",  // 1512-1519
        "safe", "sail", "salad", "salmon", "salon", "salt", "salute", "same",  // 1520-1527
        "sample", "sand", "satisfy", "satoshi", "sauce", "sausage", "save", "say",  // 1528-1535
        "scale", "scan", "scare", "scatter", "scene", "scheme", "school", "science",  // 1536-1543
        "scissors", "scorpion", "scout", "scrap", "screen", "script", "scrub", "sea",  // 1544-1551
        "search", "season", "seat", "second", "secret", "section", "security", "seed",  // 1552-1559
        "seek", "segment", "select", "sell", "seminar", "senior", "sense", "sentence",  // 1560-1567
        "series", "service", "session", "settle", "setup", "seven", "shadow", "shaft",  // 1568-1575
        "shallow", "share", "shed", "shell", "sheriff", "shield", "shift", "shine",  // 1576-1583
        "ship", "shiver", "shock", "shoe", "shoot", "shop", "short", "shoulder",  // 1584-1591
        "shove", "shrimp", "shrug", "shuffle", "shy", "sibling", "sick", "side",  // 1592-1599
        "siege", "sight", "sign", "silent", "silk", "silly", "silver", "similar",  // 1600-1607
        "simple", "since", "sing", "siren", "sister", "situate", "six", "size",  // 1608-1615
        "skate", "sketch", "ski", "skill", "skin", "skirt", "skull", "slab",  // 1616-1623
        "slam", "sleep", "slender", "slice", "slide", "slight", "slim", "slogan",  // 1624-1631
        "slot", "slow", "slush", "small", "smart", "smile", "smoke", "smooth",  // 1632-1639
        "snack", "snake", "snap", "sniff", "snow", "soap", "soccer", "social",  // 1640-1647
        "sock", "soda", "soft", "solar", "soldier", "solid", "solution", "solve",  // 1648-1655
        "someone", "song", "soon", "sorry", "sort", "soul", "sound", "soup",  // 1656-1663
        "source", "south", "space", "spare", "spatial", "spawn", "speak", "special",  // 1664-1671
        "speed", "spell", "spend", "sphere", "spice", "spider", "spike", "spin",  // 1672-1679
        "spirit", "split", "spoil", "sponsor", "spoon", "sport", "spot", "spray",  // 1680-1687
        "spread", "spring", "spy", "square", "squeeze", "squirrel", "stable", "stadium",  // 1688-1695
        "staff", "stage", "stairs", "stamp", "stand", "start", "state", "stay",  // 1696-1703
        "steak", "steel", "stem", "step", "stereo", "stick", "still", "sting",  // 1704-1711
        "stock", "stomach", "stone", "stool", "story", "stove", "strategy", "street",  // 1712-1719
        "strike", "strong", "struggle", "student", "stuff", "stumble", "style", "subject",  // 1720-1727
        "submit", "subway", "success", "such", "sudden", "suffer", "sugar", "suggest",  // 1728-1735
        "suit", "summer", "sun", "sunny", "sunset", "super", "supply", "supreme",  // 1736-1743
        "sure", "surface", "surge", "surprise", "surround", "survey", "suspect", "sustain",  // 1744-1751
        "swallow", "swamp", "swap", "swarm", "swear", "sweet", "swift", "swim",  // 1752-1759
        "swing", "switch", "sword", "symbol", "symptom", "syrup", "system", "table",  // 1760-1767
        "tackle", "tag", "tail", "talent", "talk", "tank", "tape", "target",  // 1768-1775
        "task", "taste", "tattoo", "taxi", "teach", "team", "tell", "ten",  // 1776-1783
        "tenant", "tennis", "tent", "term", "test", "text", "thank", "that",  // 1784-1791
        "theme", "then", "theory", "there", "they", "thing", "this", "thought",  // 1792-1799
        "three", "thrive", "throw", "thumb", "thunder", "ticket", "tide", "tiger",  // 1800-1807
        "tilt", "timber", "time", "tiny", "tip", "tired", "tissue", "title",  // 1808-1815
        "toast", "tobacco", "today", "toddler", "toe", "together", "toilet", "token",  // 1816-1823
        "tomato", "tomorrow", "tone", "tongue", "tonight", "tool", "tooth", "top",  // 1824-1831
        "topic", "topple", "torch", "tornado", "tortoise", "toss", "total", "tourist",  // 1832-1839
        "toward", "tower", "town", "toy", "track", "trade", "traffic", "tragic",  // 1840-1847
        "train", "transfer", "trap", "trash", "travel", "tray", "treat", "tree",  // 1848-1855
        "trend", "trial", "tribe", "trick", "trigger", "trim", "trip", "trophy",  // 1856-1863
        "trouble", "truck", "true", "truly", "trumpet", "trust", "truth", "try",  // 1864-1871
        "tube", "tuition", "tumble", "tuna", "tunnel", "turkey", "turn", "turtle",  // 1872-1879
        "twelve", "twenty", "twice", "twin", "twist", "two", "type", "typical",  // 1880-1887
        "ugly", "umbrella", "unable", "unaware", "uncle", "uncover", "under", "undo",  // 1888-1895
        "unfair", "unfold", "unhappy", "uniform", "unique", "unit", "universe", "unknown",  // 1896-1903
        "unlock", "until", "unusual", "unveil", "update", "upgrade", "uphold", "upon",  // 1904-1911
        "upper", "upset", "urban", "urge", "usage", "use", "used", "useful",  // 1912-1919
        "useless", "usual", "utility", "vacant", "vacuum", "vague", "valid", "valley",  // 1920-1927
        "valve", "van", "vanish", "vapor", "various", "vast", "vault", "vehicle",  // 1928-1935
        "velvet", "vendor", "venture", "venue", "verb", "verify", "version", "very",  // 1936-1943
        "vessel", "veteran", "viable", "vibrant", "vicious", "victory", "video", "view",  // 1944-1951
        "village", "vintage", "violin", "virtual", "virus", "visa", "visit", "visual",  // 1952-1959
        "vital", "vivid", "vocal", "voice", "void", "volcano", "volume", "vote",  // 1960-1967
        "voyage", "wage", "wagon", "wait", "walk", "wall", "walnut", "want",  // 1968-1975
        "warfare", "warm", "warrior", "wash", "wasp", "waste", "water", "wave",  // 1976-1983
        "way", "wealth", "weapon", "wear", "weasel", "weather", "web", "wedding",  // 1984-1991
        "weekend", "weird", "welcome", "west", "wet", "whale", "what", "wheat",  // 1992-1999
        "wheel", "when", "where", "whip", "whisper", "wide", "width", "wife",  // 2000-2007
        "wild", "will", "win", "window", "wine", "wing", "wink", "winner",  // 2008-2015
        "winter", "wire", "wisdom", "wise", "wish", "witness", "wolf", "woman",  // 2016-2023
        "wonder", "wood", "wool", "word", "work", "world", "worry", "worth",  // 2024-2031
        "wrap", "wreck", "wrestle", "wrist", "write", "wrong", "yard", "year",  // 2032-2039
        "yellow", "you", "young", "youth", "zebra", "zero", "zone", "zoo"  // 2040-2047
    ]

    // MARK: - Lookup Table (built lazily for O(1) lookups)

    /// Dictionary mapping words to their indices for fast lookup
    private static let wordToIndex: [String: Int] = {
        var dict = [String: Int](minimumCapacity: 2048)
        for (index, word) in english.enumerated() {
            dict[word] = index
        }
        return dict
    }()

    // MARK: - Validation

    /// Validates that a word exists in the BIP39 English wordlist
    /// - Parameter word: The word to validate (case-insensitive)
    /// - Returns: `true` if the word is in the wordlist
    static func isValid(word: String) -> Bool {
        wordToIndex[word.lowercased()] != nil
    }

    /// Returns the index of a word (0-2047) or nil if not found
    /// - Parameter word: The word to look up (case-insensitive)
    /// - Returns: The 0-based index in the wordlist, or `nil`
    static func index(of word: String) -> Int? {
        wordToIndex[word.lowercased()]
    }

    /// Returns the word at a given index, or nil if out of range
    /// - Parameter index: The 0-based index (0-2047)
    /// - Returns: The word at that index, or `nil`
    static func word(at index: Int) -> String? {
        guard index >= 0, index < english.count else { return nil }
        return english[index]
    }

    // MARK: - Integrity Check

    /// Verifies the wordlist contains exactly 2048 entries
    /// - Returns: `true` if the wordlist is intact
    static var isIntact: Bool {
        english.count == 2048
    }
}
