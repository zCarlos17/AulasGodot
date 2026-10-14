from PIL import Image

TILE = 16
QUADROS = 3

img = Image.open("GandalfHardcore Water Tiles sheet.png").convert("RGBA")
w, h = img.size
fh = h // QUADROS

assert w % TILE == 0 and fh % TILE == 0, f"Tamanho {w}x{h} não é múltiplo de 16 por quadro"

cols = w // TILE
rows = fh // TILE
saida = Image.new("RGBA", (cols * QUADROS * TILE, rows * TILE), (0, 0, 0, 0))

for f in range(QUADROS):
    quadro = img.crop((0, f * fh, w, (f + 1) * fh))
    for r in range(rows):
        for c in range(cols):
            tile = quadro.crop((c * TILE, r * TILE, c * TILE + TILE, r * TILE + TILE))
            saida.paste(tile, ((c * QUADROS + f) * TILE, r * TILE))

saida.save("agua_animada_tiles.png")
print(f"Posições: {cols} x {rows}. Cada posição tem {QUADROS} quadros.")