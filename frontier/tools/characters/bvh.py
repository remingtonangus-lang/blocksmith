"""Minimal BVH reader + forward kinematics (numpy). Used by retarget.py for the CMU (cgspeed) conversion."""
import numpy as np


class Joint:
    __slots__ = ("name", "parent", "offset", "channels", "children", "end")

    def __init__(self, name, parent):
        self.name, self.parent = name, parent
        self.offset = np.zeros(3)
        self.channels = []
        self.children = []
        self.end = None


class BVH:
    def __init__(self, path):
        self.joints = []
        self.index = {}
        with open(path) as f:
            tokens = f.read().split()
        i = 0
        stack = []
        cur = None
        while tokens[i] != "MOTION":
            t = tokens[i]
            if t in ("ROOT", "JOINT"):
                j = Joint(tokens[i + 1], stack[-1] if stack else None)
                self.index[j.name] = len(self.joints)
                self.joints.append(j)
                if j.parent is not None:
                    self.joints[j.parent].children.append(self.index[j.name])
                cur = j
                i += 2
            elif t == "End":
                cur = "end"
                i += 2
            elif t == "{":
                stack.append(self.index[self.joints[-1].name] if cur != "end" else -1)
                i += 1
            elif t == "}":
                stack.pop()
                cur = None
                i += 1
            elif t == "OFFSET":
                v = np.array([float(x) for x in tokens[i + 1:i + 4]])
                if cur == "end":
                    self.joints[stack[-2] if stack[-1] == -1 else stack[-1]].end = v
                else:
                    self.joints[-1].offset = v
                i += 4
            elif t == "CHANNELS":
                n = int(tokens[i + 1])
                self.joints[-1].channels = tokens[i + 2:i + 2 + n]
                i += 2 + n
            else:
                i += 1
        # stack bookkeeping: "End Site" pushes -1; its parent is the joint below it on the stack
        i += 1
        assert tokens[i] == "Frames:"
        nframes = int(tokens[i + 1])
        assert tokens[i + 2] == "Frame" and tokens[i + 3] == "Time:"
        self.frame_time = float(tokens[i + 4])
        vals = np.array([float(x) for x in tokens[i + 5:]], dtype=np.float64)
        nch = sum(len(j.channels) for j in self.joints)
        self.motion = vals[:nframes * nch].reshape(nframes, nch)
        self.nframes = nframes

    @staticmethod
    def _rot(axis, deg):
        a = np.radians(deg)
        c, s = np.cos(a), np.sin(a)
        n = a.shape[0]
        m = np.zeros((n, 3, 3))
        if axis == "X":
            m[:, 0, 0] = 1; m[:, 1, 1] = c; m[:, 1, 2] = -s; m[:, 2, 1] = s; m[:, 2, 2] = c
        elif axis == "Y":
            m[:, 1, 1] = 1; m[:, 0, 0] = c; m[:, 0, 2] = s; m[:, 2, 0] = -s; m[:, 2, 2] = c
        else:
            m[:, 2, 2] = 1; m[:, 0, 0] = c; m[:, 0, 1] = -s; m[:, 1, 0] = s; m[:, 1, 1] = c
        return m

    def fk(self):
        """-> (world rotations [F,J,3,3], world positions [F,J,3], end-site positions dict name->[F,3])."""
        F, J = self.nframes, len(self.joints)
        R = np.zeros((F, J, 3, 3))
        P = np.zeros((F, J, 3))
        ends = {}
        col = 0
        for ji, j in enumerate(self.joints):
            local = np.tile(np.eye(3), (F, 1, 1))
            trans = np.tile(j.offset, (F, 1))
            for ch in j.channels:
                v = self.motion[:, col]
                col += 1
                if ch.endswith("position"):
                    trans = trans.copy()
                    trans[:, "XYZ".index(ch[0])] = v + (0 if j.parent is None else j.offset["XYZ".index(ch[0])])
                else:
                    local = local @ self._rot(ch[0], v)
            if j.parent is None:
                R[:, ji] = local
                P[:, ji] = trans
            else:
                R[:, ji] = R[:, j.parent] @ local
                P[:, ji] = P[:, j.parent] + np.einsum("fij,fj->fi", R[:, j.parent], trans)
            if j.end is not None:
                ends[j.name] = P[:, ji] + np.einsum("fij,j->fi", R[:, ji], j.end)
        return R, P, ends
