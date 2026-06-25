#!/usr/bin/env python3
"""
Generador de códigos de licencia para MentalGram
Genera códigos únicos con el formato: XXXXX-XXXXX-XXXXX-XXXXX-XXXXX
"""

import random
import string
import sys

def generar_codigo():
    """Genera un código de licencia único"""
    caracteres = string.ascii_uppercase + string.digits
    segmentos = []
    
    for i in range(5):
        # Cada segmento tiene 5-6 caracteres aleatorios
        longitud = random.choice([5, 6])
        segmento = ''.join(random.choices(caracteres, k=longitud))
        segmentos.append(segmento)
    
    return '-'.join(segmentos)

def generar_multiples(cantidad=1, prefijo=None):
    """Genera múltiples códigos de licencia"""
    codigos = []
    
    for i in range(cantidad):
        if prefijo:
            # Si hay prefijo, usarlo en el primer segmento
            codigo = f"{prefijo}-"
            for j in range(4):
                longitud = random.choice([5, 6])
                segmento = ''.join(random.choices(string.ascii_uppercase + string.digits, k=longitud))
                codigo += segmento
                if j < 3:
                    codigo += "-"
        else:
            codigo = generar_codigo()
        
        codigos.append(codigo)
        print(f"{i+1}. {codigo}")
    
    return codigos

def generar_con_usuario(nombre_usuario):
    """Genera un código basado en el nombre del usuario"""
    # Limpiar y formatear el nombre del usuario
    usuario_limpio = ''.join(c for c in nombre_usuario.upper() if c.isalnum())[:5]
    
    # Rellenar si es muy corto
    while len(usuario_limpio) < 5:
        usuario_limpio += random.choice(string.ascii_uppercase)
    
    # Generar el resto de segmentos
    segmentos = [usuario_limpio]
    for i in range(4):
        longitud = random.choice([5, 6])
        segmento = ''.join(random.choices(string.ascii_uppercase + string.digits, k=longitud))
        segmentos.append(segmento)
    
    codigo = '-'.join(segmentos)
    print(f"Usuario: {nombre_usuario}")
    print(f"Código:  {codigo}")
    return codigo

def main():
    print("=" * 60)
    print("  🔑 GENERADOR DE LICENCIAS - MentalGram")
    print("=" * 60)
    print()
    
    if len(sys.argv) > 1:
        if sys.argv[1] == "--usuario" and len(sys.argv) > 2:
            # Generar con nombre de usuario
            nombre = ' '.join(sys.argv[2:])
            generar_con_usuario(nombre)
        elif sys.argv[1].isdigit():
            # Generar múltiples códigos
            cantidad = int(sys.argv[1])
            print(f"Generando {cantidad} código(s)...\n")
            generar_multiples(cantidad)
        else:
            print("Uso:")
            print("  python3 generar_licencias.py                 # Genera 1 código")
            print("  python3 generar_licencias.py 10              # Genera 10 códigos")
            print("  python3 generar_licencias.py --usuario Juan  # Genera código para 'Juan'")
    else:
        # Generar un solo código
        print("Código generado:\n")
        codigo = generar_codigo()
        print(f"  {codigo}")
    
    print()
    print("=" * 60)
    print("📝 Copia el código y añádelo a LicenseManager.swift")
    print("=" * 60)

if __name__ == "__main__":
    main()
