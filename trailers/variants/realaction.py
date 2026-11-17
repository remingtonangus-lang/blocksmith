exec(open('/tmp/jit/tr/v/common.py').read())
def cap(t, c): return (t[0], t[1], c, t[3], t[4])
CUT = [SH["rocket"](), cap(SH["flowers"](), "Build, explore and fight in a VR sandbox"), cap(SH["vbuild"](), "Build anything, block by block"),
       SH["volcano"](), SH["cave"](), cap(SH["lava"](), "Descend into the Emberdeep"), SH["train"](), SH["troops"](), SH["dropship"](),
       cap(SH["battle"](), "Raid enemy bases"), SH["snowtank"](), SH["sunsetslow"]()]
