from PIL import Image

img = Image.open("GandalfHardcore_Water_Tiles_sheet.png").convert("RGBA")

# Linhas 6 a 13 (cada tile tem 16 px): y de 96 até 224
faixa = img.crop((0, 96, img.width, 224))

quadros = []
for x in range(0, faixa.width, 16):
    coluna = faixa.crop((x, 0, x + 16, 128))
    if coluna.getchannel("A").getbbox() is not None:
        quadros.append(coluna)

saida = Image.new("RGBA", (16 * len(quadros), 128), (0, 0, 0, 0))
for i, quadro in enumerate(quadros):
    saida.paste(quadro, (i * 16, 0))
saida.save("cachoeira_quadros.png")
print("Quadros encontrados:", len(quadros))