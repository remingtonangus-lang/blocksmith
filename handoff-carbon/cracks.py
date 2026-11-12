# Count see-through specks in void-probe frames: magenta (255,0,255) components that do not touch the top edge.
import sys, os, numpy as np
from PIL import Image
from scipy import ndimage
d = sys.argv[1]; step = int(sys.argv[2]) if len(sys.argv) > 2 else 1
fs = sorted(f for f in os.listdir(d) if f.endswith('.png'))[::step]
tot = []
for f in fs:
    a = np.asarray(Image.open(os.path.join(d, f)).convert('RGB')).astype(int)
    m = (a[:,:,0] > 200) & (a[:,:,1] < 60) & (a[:,:,2] > 200)
    lab, n = ndimage.label(m)
    if n == 0: tot.append((f, 0, 0, [])); continue
    top = set(np.unique(lab[0, :])) - {0}
    sizes = ndimage.sum(m, lab, range(1, n + 1))
    objs = ndimage.find_objects(lab)
    specks = [(int(sizes[i]), objs[i]) for i in range(n) if (i + 1) not in top]
    px = sum(s for s, _ in specks)
    big = sorted(specks, key=lambda t: -t[0])[:3]
    tot.append((f, len(specks), px, [(s, o[1].start, o[0].start) for s, o in big]))
for f, n, px, big in tot:
    if n: print(f, n, 'specks', px, 'px', big)
print('frames', len(tot), 'with specks', sum(1 for t in tot if t[1]))
