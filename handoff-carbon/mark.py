import sys, numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage
src, out = sys.argv[1], sys.argv[2]
im = Image.open(src).convert('RGB'); a = np.asarray(im).astype(int)
m = (a[:,:,0] > 200) & (a[:,:,1] < 60) & (a[:,:,2] > 200)
lab, n = ndimage.label(m); top = set(np.unique(lab[0, :])) - {0}
dr = ImageDraw.Draw(im)
for i, o in enumerate(ndimage.find_objects(lab)):
    if (i + 1) in top: continue
    dr.rectangle([o[1].start - 6, o[0].start - 6, o[1].stop + 6, o[0].stop + 6], outline=(0, 255, 255), width=2)
im.save(out)
