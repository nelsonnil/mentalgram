import Foundation

// MARK: - Acrostic Word Bank
//
// 3 common words per letter per language.
// Used by AcrosticEngine to build acrostic biographies.
// When a letter repeats in the input word, the engine cycles through
// the three options so the same word never appears twice.
//
// Languages: en, es, fr, de, it, nl, pl, pt, pt-BR, ru, ja, ko,
//            zh-Hans, zh-Hant, hi, th, vi

enum AcrosticWordBank {

    // Returns 3 words for the given uppercase letter in the given language.
    // Falls back to English if the language has no entry.
    static func words(for letter: Character, language: String) -> [String] {
        let lang = language.lowercased().prefix(2)
        let table = banks[String(lang)] ?? banks["en"]!
        let key = String(letter).uppercased()
        return table[key] ?? digitFallbacks[key] ?? table["_"] ?? [String(letter)]
    }

    private static let digitFallbacks: [String: [String]] = [
        "0": ["Zero", "Circle", "Orbit"],
        "1": ["One", "Origin", "Oracle"],
        "2": ["Two", "Twin", "Trace"],
        "3": ["Three", "Thorn", "Thunder"],
        "4": ["Four", "Flame", "Field"],
        "5": ["Five", "Forest", "Fate"],
        "6": ["Six", "Silver", "Signal"],
        "7": ["Seven", "Shadow", "Star"],
        "8": ["Eight", "Echo", "Ember"],
        "9": ["Nine", "Night", "North"]
    ]

    // MARK: - All banks

    static let banks: [String: [String: [String]]] = [

        // ── English ───────────────────────────────────────────────────────────
        "en": [
            "A": ["Arrow", "Angel", "Autumn"],
            "B": ["Bridge", "Breeze", "Blade"],
            "C": ["Cloud", "Crown", "Candle"],
            "D": ["Dream", "Dawn", "Depth"],
            "E": ["Eagle", "Echo", "Earth"],
            "F": ["Flame", "Forest", "Frost"],
            "G": ["Grace", "Gold", "Gloom"],
            "H": ["Heart", "Haven", "Hollow"],
            "I": ["Island", "Iris", "Ice"],
            "J": ["Journey", "Jewel", "Jungle"],
            "K": ["Key", "Knight", "Kingdom"],
            "L": ["Light", "Lake", "Leaf"],
            "M": ["Moon", "Mirror", "Mist"],
            "N": ["Night", "North", "Name"],
            "O": ["Ocean", "Oak", "Origin"],
            "P": ["Pearl", "Path", "Power"],
            "Q": ["Quest", "Quiet", "Queen"],
            "R": ["River", "Rain", "Ridge"],
            "S": ["Stone", "Star", "Shadow"],
            "T": ["Tree", "Tide", "Tower"],
            "U": ["Union", "Urge", "Uplift"],
            "V": ["Valley", "Voice", "Vision"],
            "W": ["Wave", "Wind", "Wish"],
            "X": ["Xenon", "Xray", "Xenia"],
            "Y": ["Year", "Youth", "Yield"],
            "Z": ["Zone", "Zenith", "Zeal"],
            "_": ["Word", "Sign", "Mark"]
        ],

        // ── Spanish ───────────────────────────────────────────────────────────
        "es": [
            "A": ["Árbol", "Alma", "Azul"],
            "B": ["Brisa", "Barco", "Bosque"],
            "C": ["Cielo", "Camino", "Cristal"],
            "D": ["Destino", "Danza", "Duende"],
            "E": ["Estrella", "Espejo", "Energía"],
            "F": ["Fuego", "Flor", "Fuerza"],
            "G": ["Gloria", "Girasol", "Gracia"],
            "H": ["Horizonte", "Hogar", "Huella"],
            "I": ["Isla", "Ilusión", "Instinto"],
            "J": ["Jardín", "Joya", "Juego"],
            "K": ["Karma", "Karate", "Kiwi"],
            "L": ["Luna", "Lago", "Luz"],
            "M": ["Mar", "Magia", "Montaña"],
            "N": ["Nube", "Noche", "Norte"],
            "O": ["Ola", "Origen", "Oro"],
            "P": ["Paz", "Poder", "Piedra"],
            "Q": ["Querer", "Quietud", "Quimera"],
            "R": ["Río", "Rosa", "Rayo"],
            "S": ["Sol", "Sueño", "Sonrisa"],
            "T": ["Tierra", "Tiempo", "Torre"],
            "U": ["Universo", "Umbral", "Unión"],
            "V": ["Viento", "Valle", "Verdad"],
            "W": ["Whisky", "Web", "Watio"],
            "X": ["Xilófono", "Xenón", "Xavier"],
            "Y": ["Yerba", "Yema", "Yunque"],
            "Z": ["Zafiro", "Zona", "Zarza"],
            "_": ["Palabra", "Señal", "Marca"]
        ],

        // ── French ────────────────────────────────────────────────────────────
        "fr": [
            "A": ["Amour", "Arbre", "Aurore"],
            "B": ["Brume", "Brise", "Bougie"],
            "C": ["Ciel", "Chemin", "Cristal"],
            "D": ["Destin", "Danse", "Douceur"],
            "E": ["Étoile", "Esprit", "Écho"],
            "F": ["Flamme", "Forêt", "Force"],
            "G": ["Grâce", "Gloire", "Geste"],
            "H": ["Horizon", "Harmonie", "Heure"],
            "I": ["Île", "Image", "Instinct"],
            "J": ["Jardin", "Joie", "Joyau"],
            "K": ["Karma", "Karaté", "Kiwi"],
            "L": ["Lune", "Lumière", "Lac"],
            "M": ["Mer", "Magie", "Montagne"],
            "N": ["Nuage", "Nuit", "Nature"],
            "O": ["Onde", "Or", "Origine"],
            "P": ["Paix", "Pierre", "Pouvoir"],
            "Q": ["Quête", "Quiet", "Quintette"],
            "R": ["Rivière", "Rose", "Rêve"],
            "S": ["Soleil", "Songe", "Source"],
            "T": ["Terre", "Temps", "Tour"],
            "U": ["Univers", "Union", "Utopie"],
            "V": ["Vent", "Vallée", "Vérité"],
            "W": ["Wagon", "Web", "Watt"],
            "X": ["Xénon", "Xylophone", "Xavier"],
            "Y": ["Yoga", "Yeux", "Yeuse"],
            "Z": ["Zèle", "Zone", "Zénith"],
            "_": ["Mot", "Signe", "Marque"]
        ],

        // ── German ────────────────────────────────────────────────────────────
        "de": [
            "A": ["Abend", "Adler", "Atem"],
            "B": ["Brücke", "Baum", "Blick"],
            "C": ["Chance", "Chef", "Charme"],
            "D": ["Dunkel", "Drang", "Duft"],
            "E": ["Erde", "Echo", "Energie"],
            "F": ["Feuer", "Fluss", "Friede"],
            "G": ["Glaube", "Glanz", "Geist"],
            "H": ["Herz", "Hafen", "Höhe"],
            "I": ["Insel", "Idee", "Instinkt"],
            "J": ["Jugend", "Juwel", "Jagd"],
            "K": ["Kraft", "Klang", "Kristall"],
            "L": ["Licht", "Luft", "Leben"],
            "M": ["Meer", "Magie", "Macht"],
            "N": ["Nacht", "Nebel", "Natur"],
            "O": ["Ozean", "Ort", "Ordnung"],
            "P": ["Pfad", "Perle", "Puls"],
            "Q": ["Quelle", "Qualm", "Qual"],
            "R": ["Regen", "Rose", "Raum"],
            "S": ["Stern", "Strom", "Schatten"],
            "T": ["Traum", "Tiefe", "Tal"],
            "U": ["Universum", "Ufer", "Urwald"],
            "V": ["Wald", "Vision", "Vernunft"],
            "W": ["Welle", "Wind", "Wunsch"],
            "X": ["Xenon", "Xylofon", "Xavier"],
            "Y": ["Yoga", "Ypsilon", "Yacht"],
            "Z": ["Zeit", "Ziel", "Zufall"],
            "_": ["Wort", "Zeichen", "Spur"]
        ],

        // ── Italian ───────────────────────────────────────────────────────────
        "it": [
            "A": ["Alba", "Anima", "Azzurro"],
            "B": ["Brezza", "Bosco", "Barca"],
            "C": ["Cielo", "Cammino", "Cristallo"],
            "D": ["Destino", "Danza", "Dolcezza"],
            "E": ["Stelle", "Energia", "Eco"],
            "F": ["Fiamma", "Foresta", "Forza"],
            "G": ["Grazia", "Girasole", "Gloria"],
            "H": ["Harmonia", "Hotel", "Humus"],
            "I": ["Isola", "Illusione", "Istinto"],
            "J": ["Gioia", "Jeans", "Jazz"],
            "K": ["Karma", "Karate", "Kiwi"],
            "L": ["Luna", "Lago", "Luce"],
            "M": ["Mare", "Magia", "Montagna"],
            "N": ["Nuvola", "Notte", "Nord"],
            "O": ["Onda", "Oro", "Origine"],
            "P": ["Pace", "Pietra", "Potere"],
            "Q": ["Quiete", "Quadro", "Questione"],
            "R": ["Fiume", "Rosa", "Raggio"],
            "S": ["Sole", "Sogno", "Sorriso"],
            "T": ["Terra", "Tempo", "Torre"],
            "U": ["Universo", "Unione", "Uscita"],
            "V": ["Vento", "Valle", "Verità"],
            "W": ["Whisky", "Web", "Watt"],
            "X": ["Xilofono", "Xenon", "Ximenia"],
            "Y": ["Yoga", "Yacht", "Yogurt"],
            "Z": ["Zafiro", "Zona", "Zenith"],
            "_": ["Parola", "Segno", "Traccia"]
        ],

        // ── Dutch ─────────────────────────────────────────────────────────────
        "nl": [
            "A": ["Avond", "Adelaar", "Adem"],
            "B": ["Brug", "Boom", "Branding"],
            "C": ["Cirkel", "Chaos", "Charme"],
            "D": ["Droom", "Diepte", "Duisternis"],
            "E": ["Echo", "Energie", "Eeuwig"],
            "F": ["Vlam", "Forst", "Kracht"],
            "G": ["Geloof", "Glans", "Geest"],
            "H": ["Hart", "Haven", "Hoogte"],
            "I": ["Eiland", "Idee", "Instinct"],
            "J": ["Jeugd", "Juweel", "Jacht"],
            "K": ["Kracht", "Klank", "Kristal"],
            "L": ["Licht", "Lucht", "Leven"],
            "M": ["Zee", "Magie", "Macht"],
            "N": ["Nacht", "Nevel", "Natuur"],
            "O": ["Oceaan", "Orde", "Oorsprong"],
            "P": ["Pad", "Parel", "Puls"],
            "Q": ["Rust", "Kwart", "Kwaliteit"],
            "R": ["Regen", "Roos", "Ruimte"],
            "S": ["Ster", "Stroom", "Schaduw"],
            "T": ["Droom", "Diepte", "Dal"],
            "U": ["Universum", "Uitzicht", "Uitweg"],
            "V": ["Golf", "Visie", "Vrede"],
            "W": ["Wind", "Wensdroom", "Water"],
            "X": ["Xenon", "Xylofoon", "Xavier"],
            "Y": ["Yoga", "IJssel", "Ypsilon"],
            "Z": ["Zon", "Zee", "Ziel"],
            "_": ["Woord", "Teken", "Spoor"]
        ],

        // ── Polish ────────────────────────────────────────────────────────────
        "pl": [
            "A": ["Anioł", "Artysta", "Akcja"],
            "B": ["Burza", "Brama", "Brylant"],
            "C": ["Cisza", "Cień", "Chmura"],
            "D": ["Droga", "Drzewo", "Duch"],
            "E": ["Echo", "Energia", "Epoka"],
            "F": ["Fala", "Flaga", "Fiord"],
            "G": ["Gwiazda", "Góra", "Głos"],
            "H": ["Harmonia", "Horyzont", "Herb"],
            "I": ["Iskra", "Instynkt", "Iluzja"],
            "J": ["Jezioro", "Jaskółka", "Jutro"],
            "K": ["Kamień", "Klucz", "Kryształ"],
            "L": ["Luna", "Las", "Legenda"],
            "M": ["Morze", "Mgła", "Moc"],
            "N": ["Noc", "Niebo", "Nurt"],
            "O": ["Ocean", "Ogień", "Obraz"],
            "P": ["Perła", "Pamięć", "Puls"],
            "Q": ["Quest", "Quinta", "Quorum"],
            "R": ["Rzeka", "Rejs", "Promień"],
            "S": ["Słońce", "Sen", "Serce"],
            "T": ["Tęcza", "Tajemnica", "Trop"],
            "U": ["Uśmiech", "Utopia", "Urok"],
            "V": ["Vega", "Vibe", "Vortex"],
            "W": ["Wiatr", "Woda", "Wizja"],
            "X": ["Xenon", "Ksylofon", "Xeroks"],
            "Y": ["Yoga", "Ypsilon", "Yarrow"],
            "Z": ["Zorza", "Zamek", "Znak"],
            "_": ["Słowo", "Znak", "Ślad"]
        ],

        // ── Portuguese / PT-BR ────────────────────────────────────────────────
        "pt": [
            "A": ["Amor", "Árvore", "Aurora"],
            "B": ["Brisa", "Bosque", "Barco"],
            "C": ["Céu", "Caminho", "Cristal"],
            "D": ["Destino", "Dança", "Doçura"],
            "E": ["Estrela", "Espelho", "Energia"],
            "F": ["Fogo", "Flor", "Força"],
            "G": ["Graça", "Girassol", "Glória"],
            "H": ["Horizonte", "Harmonia", "Herança"],
            "I": ["Ilha", "Ilusão", "Instinto"],
            "J": ["Jardim", "Joia", "Jogo"],
            "K": ["Karma", "Karate", "Kiwi"],
            "L": ["Lua", "Lago", "Luz"],
            "M": ["Mar", "Magia", "Montanha"],
            "N": ["Nuvem", "Noite", "Norte"],
            "O": ["Onda", "Ouro", "Origem"],
            "P": ["Paz", "Pedra", "Poder"],
            "Q": ["Querer", "Quietude", "Quimera"],
            "R": ["Rio", "Rosa", "Raio"],
            "S": ["Sol", "Sonho", "Sorriso"],
            "T": ["Terra", "Tempo", "Torre"],
            "U": ["Universo", "União", "Umbral"],
            "V": ["Vento", "Vale", "Verdade"],
            "W": ["Web", "Watt", "Whisky"],
            "X": ["Xilofone", "Xenônio", "Xavier"],
            "Y": ["Yoga", "Yarrow", "Yield"],
            "Z": ["Zafiro", "Zona", "Zênite"],
            "_": ["Palavra", "Sinal", "Marca"]
        ],

        // ── Russian ───────────────────────────────────────────────────────────
        "ru": [
            "А": ["Арка", "Ангел", "Аура"],
            "Б": ["Буря", "Берег", "Блеск"],
            "В": ["Ветер", "Волна", "Время"],
            "Г": ["Гора", "Голос", "Глубина"],
            "Д": ["Душа", "Дорога", "Дух"],
            "Е": ["Ель", "Единство", "Ёж"],
            "Ж": ["Жизнь", "Жемчуг", "Жар"],
            "З": ["Звезда", "Земля", "Зеркало"],
            "И": ["Искра", "Иллюзия", "Инстинкт"],
            "К": ["Кристалл", "Ключ", "Корень"],
            "Л": ["Луна", "Луч", "Лес"],
            "М": ["Море", "Магия", "Мечта"],
            "Н": ["Ночь", "Небо", "Нить"],
            "О": ["Огонь", "Океан", "Облако"],
            "П": ["Путь", "Перо", "Пульс"],
            "Р": ["Река", "Роза", "Рассвет"],
            "С": ["Солнце", "Сон", "Сила"],
            "Т": ["Тень", "Тайна", "Туман"],
            "У": ["Уют", "Узор", "Утро"],
            "Ф": ["Факел", "Форма", "Фокус"],
            "Х": ["Хрусталь", "Хаос", "Холм"],
            "Ц": ["Цвет", "Цель", "Цепь"],
            "Ч": ["Чудо", "Черта", "Честь"],
            "Ш": ["Шторм", "Шёпот", "Шар"],
            "Э": ["Эхо", "Энергия", "Эпоха"],
            "Я": ["Яркость", "Якорь", "Ядро"],
            "_": ["Слово", "Знак", "След"]
        ],

        // ── Japanese (romaji initials mapped to katakana words) ───────────────
        // For Japanese, OCR/API will typically return romaji or basic kana.
        // We map A-Z to Japanese common nouns as acrostic lines.
        "ja": [
            "A": ["愛（あい）", "青空（あおぞら）", "嵐（あらし）"],
            "B": ["美（び）", "薔薇（ばら）", "星（ほし）"],
            "C": ["夢（ゆめ）", "雲（くも）", "心（こころ）"],
            "D": ["大地（だいち）", "道（みち）", "魂（たましい）"],
            "E": ["縁（えん）", "永遠（えいえん）", "笑顔（えがお）"],
            "F": ["炎（ほのお）", "風（かぜ）", "富士（ふじ）"],
            "G": ["月（つき）", "銀河（ぎんが）", "玉（たま）"],
            "H": ["花（はな）", "星（ほし）", "光（ひかり）"],
            "I": ["命（いのち）", "稲妻（いなずま）", "泉（いずみ）"],
            "K": ["空（そら）", "輝き（かがやき）", "絆（きずな）"],
            "M": ["海（うみ）", "水（みず）", "道（みち）"],
            "N": ["虹（にじ）", "波（なみ）", "夜（よる）"],
            "O": ["大空（おおぞら）", "乙女（おとめ）", "音（おと）"],
            "R": ["流れ星（ながれぼし）", "理想（りそう）", "路（みち）"],
            "S": ["桜（さくら）", "空（そら）", "魂（たましい）"],
            "T": ["太陽（たいよう）", "宝（たから）", "時（とき）"],
            "Y": ["夢（ゆめ）", "雪（ゆき）", "宵（よい）"],
            "_": ["言葉", "印", "跡"]
        ],

        // ── Korean ────────────────────────────────────────────────────────────
        "ko": [
            "A": ["아침（아침）", "사랑（사랑）", "별（별）"],
            "B": ["바람（바람）", "빛（빛）", "봄（봄）"],
            "C": ["하늘（하늘）", "빛（빛）", "길（길）"],
            "D": ["꿈（꿈）", "달（달）", "도전（도전）"],
            "G": ["기적（기적）", "길（길）", "그림（그림）"],
            "H": ["희망（희망）", "하늘（하늘）", "행복（행복）"],
            "I": ["이상（이상）", "인연（인연）", "인생（인생）"],
            "J": ["정（정）", "진심（진심）", "자유（자유）"],
            "M": ["마음（마음）", "미래（미래）", "물결（물결）"],
            "N": ["나무（나무）", "눈（눈）", "노래（노래）"],
            "S": ["사랑（사랑）", "빛（빛）", "하늘（하늘）"],
            "U": ["우주（우주）", "울림（울림）", "유산（유산）"],
            "_": ["단어", "표시", "흔적"]
        ],

        // ── Chinese Simplified ────────────────────────────────────────────────
        "zh": [
            "0": ["零（líng）", "圆（yuán）", "空（kōng）"],
            "1": ["一（yī）", "伊（yī）", "意（yì）"],
            "2": ["二（èr）", "尔（ěr）", "耳（ěr）"],
            "3": ["三（sān）", "山（shān）", "伞（sǎn）"],
            "4": ["四（sì）", "思（sī）", "诗（shī）"],
            "5": ["五（wǔ）", "舞（wǔ）", "雾（wù）"],
            "6": ["六（liù）", "流（liú）", "柳（liǔ）"],
            "7": ["七（qī）", "奇（qí）", "旗（qí）"],
            "8": ["八（bā）", "宝（bǎo）", "波（bō）"],
            "9": ["九（jiǔ）", "久（jiǔ）", "酒（jiǔ）"],
            "A": ["爱（ài）", "安（ān）", "岸（àn）"],
            "B": ["波（bō）", "博（bó）", "冰（bīng）"],
            "C": ["彩（cǎi）", "晨（chén）", "纯（chún）"],
            "D": ["道（dào）", "灯（dēng）", "梦（mèng）"],
            "E": ["恩（ēn）", "耳（ěr）", "二（èr）"],
            "F": ["风（fēng）", "福（fú）", "帆（fān）"],
            "G": ["光（guāng）", "歌（gē）", "根（gēn）"],
            "H": ["花（huā）", "河（hé）", "海（hǎi）"],
            "I": ["意（yì）", "影（yǐng）", "音（yīn）"],
            "J": ["静（jìng）", "金（jīn）", "晶（jīng）"],
            "K": ["空（kōng）", "康（kāng）", "凯（kǎi）"],
            "L": ["蓝（lán）", "灵（líng）", "雷（léi）"],
            "M": ["明（míng）", "梦（mèng）", "木（mù）"],
            "N": ["宁（níng）", "南（nán）", "念（niàn）"],
            "O": ["欧（ōu）", "鸥（ōu）", "偶（ǒu）"],
            "P": ["平（píng）", "鹏（péng）", "盼（pàn）"],
            "Q": ["清（qīng）", "泉（quán）", "琴（qín）"],
            "R": ["日（rì）", "荣（róng）", "柔（róu）"],
            "S": ["山（shān）", "诗（shī）", "水（shuǐ）"],
            "T": ["天（tiān）", "土（tǔ）", "桃（táo）"],
            "U": ["优（yōu）", "宇（yǔ）", "玉（yù）"],
            "V": ["维（wéi）", "微（wēi）", "望（wàng）"],
            "W": ["望（wàng）", "雾（wù）", "舞（wǔ）"],
            "X": ["星（xīng）", "心（xīn）", "仙（xiān）"],
            "Y": ["月（yuè）", "云（yún）", "阳（yáng）"],
            "Z": ["智（zhì）", "珠（zhū）", "竹（zhú）"],
            "_": ["词", "符", "痕"]
        ],

        // ── Hindi ─────────────────────────────────────────────────────────────
        "hi": [
            "A": ["आकाश", "आनंद", "आशा"],
            "B": ["बादल", "ब्रह्मांड", "बहार"],
            "C": ["चाँद", "चमक", "चेतना"],
            "D": ["दिल", "दर्पण", "दुनिया"],
            "E": ["ऊर्जा", "एकता", "इच्छा"],
            "G": ["गीत", "गहराई", "गंगा"],
            "J": ["जीवन", "जल", "ज्योति"],
            "K": ["किरण", "कमल", "क्षितिज"],
            "M": ["मन", "माया", "मौसम"],
            "P": ["प्रेम", "पानी", "पवन"],
            "R": ["रोशनी", "रात", "रंग"],
            "S": ["सूरज", "सपना", "सत्य"],
            "T": ["तारा", "तूफान", "तरंग"],
            "_": ["शब्द", "चिह्न", "छाप"]
        ],

        // ── Thai ──────────────────────────────────────────────────────────────
        "th": [
            "A": ["ฟ้า（ฟ้า）", "แสง（แสง）", "ความรัก（ความรัก）"],
            "B": ["ลม（ลม）", "ดาว（ดาว）", "น้ำ（น้ำ）"],
            "D": ["ดวงจันทร์（ดวงจันทร์）", "ดอกไม้（ดอกไม้）", "ดิน（ดิน）"],
            "S": ["ดวงอาทิตย์（ดวงอาทิตย์）", "ท้องฟ้า（ท้องฟ้า）", "ฝัน（ฝัน）"],
            "_": ["คำ", "สัญลักษณ์", "รอยเท้า"]
        ],

        // ── Vietnamese ────────────────────────────────────────────────────────
        "vi": [
            "A": ["Ánh sáng", "An bình", "Ái tình"],
            "B": ["Biển", "Bầu trời", "Bình minh"],
            "C": ["Cầu vồng", "Cảm xúc", "Chân trời"],
            "D": ["Dòng sông", "Đêm", "Đường đời"],
            "G": ["Giấc mơ", "Gió", "Giọt sương"],
            "H": ["Hoa", "Hành trình", "Hồn"],
            "M": ["Mặt trời", "Mây", "Mơ"],
            "N": ["Nước", "Niềm vui", "Ngọc"],
            "S": ["Sao", "Sóng", "Sức mạnh"],
            "T": ["Trăng", "Trời", "Tình yêu"],
            "_": ["Từ", "Dấu", "Vết"]
        ]
    ]
}
