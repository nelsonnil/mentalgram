#!/usr/bin/env python3
import os

BASE = "/Users/nil/Desktop/MentalGram1/MentalGram1"

translations = {
    "es": {
        "set.input.cardclock.help": "En Performance, desliza en cualquier dirección sobre la cuadrícula. Siempre 4 swipes: primer par = valor, segundo par = palo. Mantén pulsado para confirmar.",
        "set.input.cardclock.values": "Codificación de valor  (cara del reloj)",
        "set.input.cardclock.suits": "Codificación de palo  (misma dirección dos veces)",
        "set.input.cardclock.longpress": "Mantén pulsado en cualquier lugar de la cuadrícula para confirmar y revelar.",
        "set.input.cardclock.noconfig": "No se requiere configuración.",
    },
    "de": {
        "set.input.cardclock.help": "In Performance wischen Sie in beliebiger Richtung auf dem Raster. Immer 4 Wischgesten: erstes Paar = Kartenwert, zweites Paar = Farbe. Lang drücken zum Bestätigen.",
        "set.input.cardclock.values": "Wertkodierung  (Zifferblatt)",
        "set.input.cardclock.suits": "Farbkodierung  (dieselbe Richtung zweimal)",
        "set.input.cardclock.longpress": "Irgendwo auf dem Raster lang drücken, um zu bestätigen.",
        "set.input.cardclock.noconfig": "Keine Konfiguration erforderlich.",
    },
    "fr": {
        "set.input.cardclock.help": "En Performance, glissez dans n'importe quelle direction sur la grille. Toujours 4 glissements : premier duo = valeur, second duo = couleur. Appuyez longuement pour confirmer.",
        "set.input.cardclock.values": "Encodage de la valeur  (cadran d'horloge)",
        "set.input.cardclock.suits": "Encodage de la couleur  (même direction deux fois)",
        "set.input.cardclock.longpress": "Appuyez longuement n'importe où sur la grille pour confirmer.",
        "set.input.cardclock.noconfig": "Aucune configuration requise.",
    },
    "it": {
        "set.input.cardclock.help": "In Performance, scorri in qualsiasi direzione sulla griglia. Sempre 4 swipe: prima coppia = valore, seconda coppia = seme. Tieni premuto per confermare.",
        "set.input.cardclock.values": "Codifica del valore  (quadrante orologio)",
        "set.input.cardclock.suits": "Codifica del seme  (stessa direzione due volte)",
        "set.input.cardclock.longpress": "Tieni premuto ovunque sulla griglia per confermare.",
        "set.input.cardclock.noconfig": "Nessuna configurazione richiesta.",
    },
    "pt": {
        "set.input.cardclock.help": "Em Performance, deslize em qualquer direção na grelha. Sempre 4 deslizamentos: primeiro par = valor, segundo par = naipe. Prima longa para confirmar.",
        "set.input.cardclock.values": "Codificação de valor  (mostrador do relógio)",
        "set.input.cardclock.suits": "Codificação de naipe  (mesma direção duas vezes)",
        "set.input.cardclock.longpress": "Prima longa em qualquer lugar da grelha para confirmar.",
        "set.input.cardclock.noconfig": "Nenhuma configuração necessária.",
    },
    "pt-BR": {
        "set.input.cardclock.help": "Em Performance, deslize em qualquer direção na grade. Sempre 4 gestos: primeiro par = valor, segundo par = naipe. Pressione e segure para confirmar.",
        "set.input.cardclock.values": "Codificação de valor  (mostrador do relógio)",
        "set.input.cardclock.suits": "Codificação de naipe  (mesma direção duas vezes)",
        "set.input.cardclock.longpress": "Pressione e segure em qualquer lugar da grade para confirmar.",
        "set.input.cardclock.noconfig": "Nenhuma configuração necessária.",
    },
    "nl": {
        "set.input.cardclock.help": "In Performance veeg in beliebige richting over het raster. Altijd 4 vegen: eerste paar = waarde, tweede paar = kleur. Houd ingedrukt om te bevestigen.",
        "set.input.cardclock.values": "Waardecode  (klokwijzerplaat)",
        "set.input.cardclock.suits": "Kleurcode  (dezelfde richting tweemaal)",
        "set.input.cardclock.longpress": "Houd ergens op het raster ingedrukt om te bevestigen.",
        "set.input.cardclock.noconfig": "Geen configuratie vereist.",
    },
    "pl": {
        "set.input.cardclock.help": "W Performance przesuń w dowolnym kierunku po siatce. Zawsze 4 gesty: pierwsza para = wartość, druga para = kolor. Przytrzymaj, aby potwierdzić.",
        "set.input.cardclock.values": "Kodowanie wartości  (tarczа zegara)",
        "set.input.cardclock.suits": "Kodowanie koloru  (ten sam kierunek dwa razy)",
        "set.input.cardclock.longpress": "Przytrzymaj w dowolnym miejscu siatki, aby potwierdzić.",
        "set.input.cardclock.noconfig": "Konfiguracja nie jest wymagana.",
    },
    "ru": {
        "set.input.cardclock.help": "В Performance проведите пальцем в любом направлении по сетке. Всегда 4 свайпа: первая пара = значение, вторая = масть. Нажмите и удерживайте для подтверждения.",
        "set.input.cardclock.values": "Кодировка значения  (циферблат часов)",
        "set.input.cardclock.suits": "Кодировка масти  (одинаковое направление дважды)",
        "set.input.cardclock.longpress": "Нажмите и удерживайте в любом месте сетки для подтверждения.",
        "set.input.cardclock.noconfig": "Настройка не требуется.",
    },
    "ja": {
        "set.input.cardclock.help": "Performanceで、フォトグリッド上を任意の方向にスワイプします。常に4スワイプ：最初のペア=カード値、2番目=スート。長押しで確定。",
        "set.input.cardclock.values": "数値エンコード  （時計の文字盤）",
        "set.input.cardclock.suits": "スートエンコード  （同じ方向を2回）",
        "set.input.cardclock.longpress": "グリッド上を長押しして確定・リビールします。",
        "set.input.cardclock.noconfig": "設定は不要です。",
    },
    "ko": {
        "set.input.cardclock.help": "Performance에서 그리드 위를 임의 방향으로 스와이프하세요. 항상 4번: 첫 쌍 = 카드 값, 둘째 쌍 = 수트. 길게 눌러 확인.",
        "set.input.cardclock.values": "숫자 인코딩  (시계 문자판)",
        "set.input.cardclock.suits": "수트 인코딩  (같은 방향 두 번)",
        "set.input.cardclock.longpress": "그리드 아무 곳이나 길게 눌러 확인하세요.",
        "set.input.cardclock.noconfig": "구성이 필요 없습니다.",
    },
    "zh-Hans": {
        "set.input.cardclock.help": "在 Performance 中，在照片网格上向任意方向滑动。始终 4 次滑动：前两次 = 牌面值，后两次 = 花色。长按以确认。",
        "set.input.cardclock.values": "点数编码  （时钟表盘）",
        "set.input.cardclock.suits": "花色编码  （同一方向两次）",
        "set.input.cardclock.longpress": "在网格任意位置长按以确认并触发 reveal。",
        "set.input.cardclock.noconfig": "无需配置。",
    },
    "zh-Hant": {
        "set.input.cardclock.help": "在 Performance 中，在照片格狀圖上向任意方向滑動。始終 4 次滑動：前兩次 = 牌面值，後兩次 = 花色。長按以確認。",
        "set.input.cardclock.values": "點數編碼  （時鐘錶盤）",
        "set.input.cardclock.suits": "花色編碼  （同一方向兩次）",
        "set.input.cardclock.longpress": "在格狀圖任意位置長按以確認並觸發 reveal。",
        "set.input.cardclock.noconfig": "無需配置。",
    },
    "hi": {
        "set.input.cardclock.help": "Performance में, फ़ोटो ग्रिड पर किसी भी दिशा में स्वाइप करें। हमेशा 4 स्वाइप: पहला जोड़ा = मान, दूसरा = सूट। पुष्टि के लिए लंबे समय तक दबाएं।",
        "set.input.cardclock.values": "मूल्य कोडिंग  (घड़ी की डायल)",
        "set.input.cardclock.suits": "सूट कोडिंग  (एक ही दिशा दो बार)",
        "set.input.cardclock.longpress": "पुष्टि के लिए ग्रिड पर कहीं भी लंबे समय तक दबाएं।",
        "set.input.cardclock.noconfig": "कोई कॉन्फ़िगरेशन आवश्यक नहीं।",
    },
    "th": {
        "set.input.cardclock.help": "ใน Performance ให้ปัดนิ้วในทิศทางใดก็ได้บนกริด เสมอ 4 ครั้ง: คู่แรก = ค่า คู่ที่สอง = ดอกไพ่ กดค้างเพื่อยืนยัน",
        "set.input.cardclock.values": "การเข้ารหัสค่า  (หน้าปัดนาฬิกา)",
        "set.input.cardclock.suits": "การเข้ารหัสดอก  (ทิศทางเดียวกันสองครั้ง)",
        "set.input.cardclock.longpress": "กดค้างที่ใดก็ได้บนกริดเพื่อยืนยัน",
        "set.input.cardclock.noconfig": "ไม่ต้องตั้งค่า",
    },
    "vi": {
        "set.input.cardclock.help": "Trong Performance, vuốt theo bất kỳ hướng nào trên lưới. Luôn 4 vuốt: cặp đầu = giá trị, cặp sau = chất. Nhấn giữ để xác nhận.",
        "set.input.cardclock.values": "Mã hóa giá trị  (mặt đồng hồ)",
        "set.input.cardclock.suits": "Mã hóa chất  (cùng hướng hai lần)",
        "set.input.cardclock.longpress": "Nhấn giữ bất kỳ vị trí nào trên lưới để xác nhận.",
        "set.input.cardclock.noconfig": "Không cần cấu hình.",
    },
}

KEYS = ["set.input.cardclock.help","set.input.cardclock.values",
        "set.input.cardclock.suits","set.input.cardclock.longpress",
        "set.input.cardclock.noconfig"]

SECTION = "\n// MARK: - Card Clock Input config\n"

for lang, trans in translations.items():
    path = os.path.join(BASE, f"{lang}.lproj", "Localizable.strings")
    if not os.path.exists(path):
        print(f"⚠️  {path}"); continue
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()
    if '"set.input.cardclock.help"' in content:
        print(f"—   {lang} (ya existe)"); continue
    block = SECTION
    for k in KEYS:
        block += f'"{k}" = "{trans[k]}";\n'
    with open(path, "a", encoding="utf-8") as f:
        f.write(block)
    print(f"✅  {lang}")

print("Listo.")
