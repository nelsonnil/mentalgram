#!/usr/bin/env python3
import os

BASE = "/Users/nil/Desktop/MentalGram1/MentalGram1"

KEYS = [
    "postpred.help.input.cardclock.label",
    "postpred.help.input.cardclock.guide.intro",
    "postpred.help.input.cardclock.guide.values",
    "postpred.help.input.cardclock.guide.suits",
    "postpred.help.input.cardclock.guide.examples",
    "postpred.help.input.cardclock.guide.ex.js",
    "postpred.help.input.cardclock.guide.ex.3h",
    "postpred.help.input.cardclock.guide.ex.ad",
    "postpred.help.input.cardclock.guide.longpress",
]

translations = {
    "es": {
        "postpred.help.input.cardclock.label": "RELOJ DE CARTA",
        "postpred.help.input.cardclock.guide.intro": "Desliza en cualquier dirección sobre la cuadrícula de fotos de Instagram — siempre 4 swipes: los 2 primeros codifican el valor (A–K), los 2 últimos el palo. Mantén pulsado para confirmar y disparar el reveal.",
        "postpred.help.input.cardclock.guide.values": "CODIFICACIÓN DE VALOR  (cara del reloj)",
        "postpred.help.input.cardclock.guide.suits": "CODIFICACIÓN DE PALO  (misma dirección dos veces)",
        "postpred.help.input.cardclock.guide.examples": "EJEMPLOS",
        "postpred.help.input.cardclock.guide.ex.js": "Jota de Picas: ←↑ (valor J) + ↑↑ (picas)",
        "postpred.help.input.cardclock.guide.ex.3h": "3 de Corazones: →→ (valor 3) + →→ (corazones)",
        "postpred.help.input.cardclock.guide.ex.ad": "As de Diamantes: ↑→ (valor As) + ←← (diamantes)",
        "postpred.help.input.cardclock.guide.longpress": "Tras el 4.º swipe, mantén pulsado en cualquier lugar de la cuadrícula para confirmar. La foto de la carta correspondiente se desarchiva automáticamente.",
    },
    "de": {
        "postpred.help.input.cardclock.label": "KARTENUHR",
        "postpred.help.input.cardclock.guide.intro": "Wische in beliebiger Richtung auf dem Instagram-Raster — immer 4 Wischgesten: die ersten 2 kodieren den Kartenwert (A–K), die letzten 2 die Farbe. Lang drücken zum Bestätigen.",
        "postpred.help.input.cardclock.guide.values": "WERTKODIERUNG  (Zifferblatt)",
        "postpred.help.input.cardclock.guide.suits": "FARBKODIERUNG  (dieselbe Richtung zweimal)",
        "postpred.help.input.cardclock.guide.examples": "BEISPIELE",
        "postpred.help.input.cardclock.guide.ex.js": "Bube Pik: ←↑ (Wert J) + ↑↑ (Pik)",
        "postpred.help.input.cardclock.guide.ex.3h": "3 Herz: →→ (Wert 3) + →→ (Herz)",
        "postpred.help.input.cardclock.guide.ex.ad": "Ass Karo: ↑→ (Wert As) + ←← (Karo)",
        "postpred.help.input.cardclock.guide.longpress": "Nach dem 4. Wischen lang drücken, um zu bestätigen. Das zugehörige Kartenfoto wird automatisch de-archiviert.",
    },
    "fr": {
        "postpred.help.input.cardclock.label": "HORLOGE CARTE",
        "postpred.help.input.cardclock.guide.intro": "Glissez dans n'importe quelle direction sur la grille Instagram — toujours 4 glissements : les 2 premiers encodent la valeur (A–K), les 2 derniers la couleur. Appuyez longuement pour confirmer.",
        "postpred.help.input.cardclock.guide.values": "ENCODAGE DE LA VALEUR  (cadran d'horloge)",
        "postpred.help.input.cardclock.guide.suits": "ENCODAGE DE LA COULEUR  (même direction deux fois)",
        "postpred.help.input.cardclock.guide.examples": "EXEMPLES",
        "postpred.help.input.cardclock.guide.ex.js": "Valet de Pique : ←↑ (valeur V) + ↑↑ (pique)",
        "postpred.help.input.cardclock.guide.ex.3h": "3 de Cœur : →→ (valeur 3) + →→ (cœur)",
        "postpred.help.input.cardclock.guide.ex.ad": "As de Carreau : ↑→ (valeur As) + ←← (carreau)",
        "postpred.help.input.cardclock.guide.longpress": "Après le 4e glissement, appuyez longuement pour confirmer. La photo de la carte se désarchive automatiquement.",
    },
    "it": {
        "postpred.help.input.cardclock.label": "OROLOGIO CARTA",
        "postpred.help.input.cardclock.guide.intro": "Scorri in qualsiasi direzione sulla griglia Instagram — sempre 4 swipe: i primi 2 codificano il valore (A–K), gli ultimi 2 il seme. Tieni premuto per confermare.",
        "postpred.help.input.cardclock.guide.values": "CODIFICA DEL VALORE  (quadrante orologio)",
        "postpred.help.input.cardclock.guide.suits": "CODIFICA DEL SEME  (stessa direzione due volte)",
        "postpred.help.input.cardclock.guide.examples": "ESEMPI",
        "postpred.help.input.cardclock.guide.ex.js": "Fante di Picche: ←↑ (valore J) + ↑↑ (picche)",
        "postpred.help.input.cardclock.guide.ex.3h": "3 di Cuori: →→ (valore 3) + →→ (cuori)",
        "postpred.help.input.cardclock.guide.ex.ad": "Asso di Quadri: ↑→ (valore A) + ←← (quadri)",
        "postpred.help.input.cardclock.guide.longpress": "Dopo il 4° swipe, tieni premuto per confermare. La foto della carta si disarchivia automaticamente.",
    },
    "pt": {
        "postpred.help.input.cardclock.label": "RELÓGIO DE CARTA",
        "postpred.help.input.cardclock.guide.intro": "Deslize em qualquer direção na grelha Instagram — sempre 4 deslizamentos: os 2 primeiros codificam o valor (A–K), os 2 últimos o naipe. Prima longa para confirmar.",
        "postpred.help.input.cardclock.guide.values": "CODIFICAÇÃO DE VALOR  (mostrador do relógio)",
        "postpred.help.input.cardclock.guide.suits": "CODIFICAÇÃO DE NAIPE  (mesma direção duas vezes)",
        "postpred.help.input.cardclock.guide.examples": "EXEMPLOS",
        "postpred.help.input.cardclock.guide.ex.js": "Valete de Espadas: ←↑ (valor J) + ↑↑ (espadas)",
        "postpred.help.input.cardclock.guide.ex.3h": "3 de Copas: →→ (valor 3) + →→ (copas)",
        "postpred.help.input.cardclock.guide.ex.ad": "Ás de Ouros: ↑→ (valor A) + ←← (ouros)",
        "postpred.help.input.cardclock.guide.longpress": "Após o 4.º gesto, prima longa para confirmar. A foto da carta desarchiva-se automaticamente.",
    },
    "pt-BR": {
        "postpred.help.input.cardclock.label": "RELÓGIO DE CARTA",
        "postpred.help.input.cardclock.guide.intro": "Deslize em qualquer direção na grade Instagram — sempre 4 gestos: os 2 primeiros codificam o valor (A–K), os 2 últimos o naipe. Pressione e segure para confirmar.",
        "postpred.help.input.cardclock.guide.values": "CODIFICAÇÃO DE VALOR  (mostrador do relógio)",
        "postpred.help.input.cardclock.guide.suits": "CODIFICAÇÃO DE NAIPE  (mesma direção duas vezes)",
        "postpred.help.input.cardclock.guide.examples": "EXEMPLOS",
        "postpred.help.input.cardclock.guide.ex.js": "Valete de Espadas: ←↑ (valor J) + ↑↑ (espadas)",
        "postpred.help.input.cardclock.guide.ex.3h": "3 de Copas: →→ (valor 3) + →→ (copas)",
        "postpred.help.input.cardclock.guide.ex.ad": "Ás de Ouros: ↑→ (valor A) + ←← (ouros)",
        "postpred.help.input.cardclock.guide.longpress": "Após o 4.º gesto, pressione e segure para confirmar. A foto da carta é desarquivada automaticamente.",
    },
    "nl": {
        "postpred.help.input.cardclock.label": "KAARTKLOK",
        "postpred.help.input.cardclock.guide.intro": "Veeg in beliebige richting over het Instagram-raster — altijd 4 vegen: de eerste 2 coderen de waarde (A–K), de laatste 2 de kleur. Houd ingedrukt om te bevestigen.",
        "postpred.help.input.cardclock.guide.values": "WAARDECODE  (klokwijzerplaat)",
        "postpred.help.input.cardclock.guide.suits": "KLEURCODE  (dezelfde richting tweemaal)",
        "postpred.help.input.cardclock.guide.examples": "VOORBEELDEN",
        "postpred.help.input.cardclock.guide.ex.js": "Boer Schoppen: ←↑ (waarde J) + ↑↑ (schoppen)",
        "postpred.help.input.cardclock.guide.ex.3h": "3 Harten: →→ (waarde 3) + →→ (harten)",
        "postpred.help.input.cardclock.guide.ex.ad": "Aas Ruiten: ↑→ (waarde A) + ←← (ruiten)",
        "postpred.help.input.cardclock.guide.longpress": "Na de 4e veeg houd ingedrukt om te bevestigen. De bijbehorende kaartfoto wordt automatisch gedearchiveerd.",
    },
    "pl": {
        "postpred.help.input.cardclock.label": "ZEGAR KART",
        "postpred.help.input.cardclock.guide.intro": "Przesuń w dowolnym kierunku po siatce Instagram — zawsze 4 gesty: pierwsze 2 kodują wartość (A–K), ostatnie 2 kolor. Przytrzymaj, aby potwierdzić.",
        "postpred.help.input.cardclock.guide.values": "KODOWANIE WARTOŚCI  (tarcza zegara)",
        "postpred.help.input.cardclock.guide.suits": "KODOWANIE KOLORU  (ten sam kierunek dwa razy)",
        "postpred.help.input.cardclock.guide.examples": "PRZYKŁADY",
        "postpred.help.input.cardclock.guide.ex.js": "Walet Pik: ←↑ (wartość J) + ↑↑ (pik)",
        "postpred.help.input.cardclock.guide.ex.3h": "3 Kier: →→ (wartość 3) + →→ (kier)",
        "postpred.help.input.cardclock.guide.ex.ad": "As Karo: ↑→ (wartość A) + ←← (karo)",
        "postpred.help.input.cardclock.guide.longpress": "Po 4. geście przytrzymaj, aby potwierdzić. Zdjęcie karty zostanie automatycznie odarchiwizowane.",
    },
    "ru": {
        "postpred.help.input.cardclock.label": "КАРТОЧНЫЕ ЧАСЫ",
        "postpred.help.input.cardclock.guide.intro": "Проводите пальцем в любом направлении по сетке Instagram — всегда 4 свайпа: первые 2 кодируют значение (A–K), последние 2 — масть. Нажмите и удерживайте для подтверждения.",
        "postpred.help.input.cardclock.guide.values": "КОДИРОВКА ЗНАЧЕНИЯ  (циферблат часов)",
        "postpred.help.input.cardclock.guide.suits": "КОДИРОВКА МАСТИ  (одинаковое направление дважды)",
        "postpred.help.input.cardclock.guide.examples": "ПРИМЕРЫ",
        "postpred.help.input.cardclock.guide.ex.js": "Валет Пик: ←↑ (значение J) + ↑↑ (пики)",
        "postpred.help.input.cardclock.guide.ex.3h": "3 Червей: →→ (значение 3) + →→ (червы)",
        "postpred.help.input.cardclock.guide.ex.ad": "Туз Бубен: ↑→ (значение A) + ←← (бубны)",
        "postpred.help.input.cardclock.guide.longpress": "После 4-го свайпа нажмите и удерживайте для подтверждения. Фото карты разархивируется автоматически.",
    },
    "ja": {
        "postpred.help.input.cardclock.label": "カードクロック",
        "postpred.help.input.cardclock.guide.intro": "Instagramの写真グリッド上を任意の方向にスワイプ — 常に4回：最初の2回でカード値（A〜K）、後の2回でスートをエンコード。長押しで確定。",
        "postpred.help.input.cardclock.guide.values": "数値エンコード  （時計の文字盤）",
        "postpred.help.input.cardclock.guide.suits": "スートエンコード  （同じ方向を2回）",
        "postpred.help.input.cardclock.guide.examples": "例",
        "postpred.help.input.cardclock.guide.ex.js": "スペードのJ: ←↑（J値）＋↑↑（スペード）",
        "postpred.help.input.cardclock.guide.ex.3h": "ハートの3: →→（3値）＋→→（ハート）",
        "postpred.help.input.cardclock.guide.ex.ad": "ダイヤのA: ↑→（A値）＋←←（ダイヤ）",
        "postpred.help.input.cardclock.guide.longpress": "4回目のスワイプ後、グリッド上を長押しして確定。該当カードの写真が自動的にリビールされます。",
    },
    "ko": {
        "postpred.help.input.cardclock.label": "카드 클록",
        "postpred.help.input.cardclock.guide.intro": "Instagram 그리드 위를 임의 방향으로 스와이프 — 항상 4번: 처음 2번은 값(A~K), 마지막 2번은 수트 인코딩. 길게 눌러 확인.",
        "postpred.help.input.cardclock.guide.values": "숫자 인코딩  (시계 문자판)",
        "postpred.help.input.cardclock.guide.suits": "수트 인코딩  (같은 방향 두 번)",
        "postpred.help.input.cardclock.guide.examples": "예시",
        "postpred.help.input.cardclock.guide.ex.js": "스페이드 J: ←↑(J값) + ↑↑(스페이드)",
        "postpred.help.input.cardclock.guide.ex.3h": "하트 3: →→(3값) + →→(하트)",
        "postpred.help.input.cardclock.guide.ex.ad": "다이아몬드 A: ↑→(A값) + ←←(다이아몬드)",
        "postpred.help.input.cardclock.guide.longpress": "4번째 스와이프 후 길게 눌러 확인하세요. 해당 카드 사진이 자동으로 공개됩니다.",
    },
    "zh-Hans": {
        "postpred.help.input.cardclock.label": "牌面时钟",
        "postpred.help.input.cardclock.guide.intro": "在 Instagram 网格上向任意方向滑动 — 始终 4 次滑动：前 2 次编码牌面值（A–K），后 2 次编码花色。长按以确认。",
        "postpred.help.input.cardclock.guide.values": "点数编码  （时钟表盘）",
        "postpred.help.input.cardclock.guide.suits": "花色编码  （同一方向两次）",
        "postpred.help.input.cardclock.guide.examples": "示例",
        "postpred.help.input.cardclock.guide.ex.js": "黑桃J: ←↑（J值）+ ↑↑（黑桃）",
        "postpred.help.input.cardclock.guide.ex.3h": "红心3: →→（3值）+ →→（红心）",
        "postpred.help.input.cardclock.guide.ex.ad": "方块A: ↑→（A值）+ ←←（方块）",
        "postpred.help.input.cardclock.guide.longpress": "第4次滑动后，长按网格任意位置确认。对应的牌照片自动被取消归档。",
    },
    "zh-Hant": {
        "postpred.help.input.cardclock.label": "牌面時鐘",
        "postpred.help.input.cardclock.guide.intro": "在 Instagram 格狀圖上向任意方向滑動 — 始終 4 次：前 2 次編碼牌面值（A–K），後 2 次編碼花色。長按以確認。",
        "postpred.help.input.cardclock.guide.values": "點數編碼  （時鐘錶盤）",
        "postpred.help.input.cardclock.guide.suits": "花色編碼  （同一方向兩次）",
        "postpred.help.input.cardclock.guide.examples": "範例",
        "postpred.help.input.cardclock.guide.ex.js": "黑桃J: ←↑（J值）+ ↑↑（黑桃）",
        "postpred.help.input.cardclock.guide.ex.3h": "紅心3: →→（3值）+ →→（紅心）",
        "postpred.help.input.cardclock.guide.ex.ad": "方塊A: ↑→（A值）+ ←←（方塊）",
        "postpred.help.input.cardclock.guide.longpress": "第4次滑動後，長按格狀圖任意位置確認。對應牌照片自動被取消歸檔。",
    },
    "hi": {
        "postpred.help.input.cardclock.label": "कार्ड क्लॉक",
        "postpred.help.input.cardclock.guide.intro": "Instagram ग्रिड पर किसी भी दिशा में स्वाइप करें — हमेशा 4 बार: पहले 2 मान (A–K) कोड करते हैं, अंतिम 2 सूट। पुष्टि के लिए लंबे समय तक दबाएं।",
        "postpred.help.input.cardclock.guide.values": "मूल्य कोडिंग  (घड़ी की डायल)",
        "postpred.help.input.cardclock.guide.suits": "सूट कोडिंग  (एक ही दिशा दो बार)",
        "postpred.help.input.cardclock.guide.examples": "उदाहरण",
        "postpred.help.input.cardclock.guide.ex.js": "स्पेड्स का जैक: ←↑ (J मान) + ↑↑ (स्पेड्स)",
        "postpred.help.input.cardclock.guide.ex.3h": "हार्ट्स का 3: →→ (3 मान) + →→ (हार्ट्स)",
        "postpred.help.input.cardclock.guide.ex.ad": "डायमंड का इक्का: ↑→ (A मान) + ←← (डायमंड)",
        "postpred.help.input.cardclock.guide.longpress": "4वें स्वाइप के बाद पुष्टि के लिए लंबे समय तक दबाएं। संबंधित कार्ड फोटो स्वचालित रूप से प्रकट होती है।",
    },
    "th": {
        "postpred.help.input.cardclock.label": "นาฬิกาไพ่",
        "postpred.help.input.cardclock.guide.intro": "ปัดนิ้วในทิศทางใดก็ได้บนกริด Instagram — เสมอ 4 ครั้ง: 2 ครั้งแรกระบุค่า (A–K) 2 ครั้งหลังระบุดอก กดค้างเพื่อยืนยัน",
        "postpred.help.input.cardclock.guide.values": "การเข้ารหัสค่า  (หน้าปัดนาฬิกา)",
        "postpred.help.input.cardclock.guide.suits": "การเข้ารหัสดอก  (ทิศทางเดียวกันสองครั้ง)",
        "postpred.help.input.cardclock.guide.examples": "ตัวอย่าง",
        "postpred.help.input.cardclock.guide.ex.js": "J โพดำ: ←↑ (ค่า J) + ↑↑ (โพดำ)",
        "postpred.help.input.cardclock.guide.ex.3h": "3 ใจแดง: →→ (ค่า 3) + →→ (ใจแดง)",
        "postpred.help.input.cardclock.guide.ex.ad": "A ข้าวหลามตัด: ↑→ (ค่า A) + ←← (ข้าวหลามตัด)",
        "postpred.help.input.cardclock.guide.longpress": "หลังจากปัดครั้งที่ 4 กดค้างเพื่อยืนยัน ภาพไพ่ที่ตรงกันจะถูกเปิดเผยโดยอัตโนมัติ",
    },
    "vi": {
        "postpred.help.input.cardclock.label": "ĐỒNG HỒ BÀI",
        "postpred.help.input.cardclock.guide.intro": "Vuốt theo bất kỳ hướng nào trên lưới Instagram — luôn 4 vuốt: 2 đầu mã hóa giá trị (A–K), 2 cuối mã hóa chất. Nhấn giữ để xác nhận.",
        "postpred.help.input.cardclock.guide.values": "MÃ HÓA GIÁ TRỊ  (mặt đồng hồ)",
        "postpred.help.input.cardclock.guide.suits": "MÃ HÓA CHẤT  (cùng hướng hai lần)",
        "postpred.help.input.cardclock.guide.examples": "VÍ DỤ",
        "postpred.help.input.cardclock.guide.ex.js": "J Bích: ←↑ (giá trị J) + ↑↑ (bích)",
        "postpred.help.input.cardclock.guide.ex.3h": "3 Cơ: →→ (giá trị 3) + →→ (cơ)",
        "postpred.help.input.cardclock.guide.ex.ad": "A Rô: ↑→ (giá trị A) + ←← (rô)",
        "postpred.help.input.cardclock.guide.longpress": "Sau lần vuốt thứ 4, nhấn giữ để xác nhận. Ảnh lá bài tương ứng sẽ tự động được hiển thị.",
    },
}

SECTION = "\n// MARK: - Card Clock user guide\n"

for lang, trans in translations.items():
    path = os.path.join(BASE, f"{lang}.lproj", "Localizable.strings")
    if not os.path.exists(path):
        print(f"⚠️  {path}"); continue
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()
    if '"postpred.help.input.cardclock.label"' in content:
        print(f"—   {lang} (ya existe)"); continue
    block = SECTION
    for k in KEYS:
        block += f'"{k}" = "{trans[k]}";\n'
    with open(path, "a", encoding="utf-8") as f:
        f.write(block)
    print(f"✅  {lang}")

print("Listo.")
