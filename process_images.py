import os
from PIL import Image

def make_transparent(file_path, target_colors, tolerance=20):
    img = Image.open(file_path).convert('RGBA')
    data = img.getdata()
    
    new_data = []
    for item in data:
        r, g, b, a = item
        # Check if color is close to any of the target colors
        is_bg = False
        for tc in target_colors:
            tr, tg, tb = tc
            if abs(r - tr) < tolerance and abs(g - tg) < tolerance and abs(b - tb) < tolerance:
                is_bg = True
                break
        
        if is_bg:
            new_data.append((255, 255, 255, 0))
        else:
            new_data.append(item)
            
    img.putdata(new_data)
    img.save(file_path, 'PNG')

folder = 'assets/images/vehicles'
bg_colors = [(26, 36, 64), (11, 16, 32), (0, 0, 0)] # #1A2440, #0B1020, Black
for filename in os.listdir(folder):
    if filename.endswith('.png'):
        make_transparent(os.path.join(folder, filename), bg_colors)
