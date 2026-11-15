import unittest
from tools.assembler import assemble, AssemblyError

class AssemblerTests(unittest.TestCase):
    def test_add_golden(self):
        self.assertEqual(assemble("LDI r1, 2\nLDI r2, 3\nADD r3,r1,r2\nRET"),
                         [0x30400002, 0x30800003, 0x00c48000, 0x58000000])
    def test_labels(self):
        self.assertEqual(assemble("start: BR end\nBR start\nend: RET"),
                         [0x54000001,0x54003ffe,0x58000000])
    def test_li_and_labels(self):
        self.assertEqual(assemble("BR end\nLI r1, -1, r2\nend: RET"),
                         [0x54000003,0x3443ffff,0x30803fff,0x0c448000,0x58000000])
    def test_memory(self):
        self.assertEqual(assemble("LDR r3, -4(r1)\nSTR r3, 8(r2)"),
                         [0x64c43ffc,0x6808c008])
    def test_special(self):
        self.assertEqual(assemble("RDSR r1, LANE_ID\nBALLOT r2,r1\nMIN r3,r1,r2\nMAX r3,r1,r2"),
                         [0x38400000,0x4c840000,0x28c48000,0x2cc48000])
    def test_reject_bad_input(self):
        for text in ["ADD r16,r0,r0","LDI r1,-1","SHL r1,r2,32","BR missing",
                     "x: RET\nx: RET","LI r1,5,r1","LDR r1,8192(r2)",
                     "RDSR r1,4","ADD r1,r2","NOPE","BR 8192"]:
            with self.subTest(text=text), self.assertRaises(AssemblyError): assemble(text)
    def test_full_instruction_set(self):
        for text in ['SUB r1,r2,r3','AND r1,r2,r3','OR r1,r2,r3','XOR r1,r2,r3',
                     'SLT r1,r2,r3','MUL r1,r2,r3','SEQ r1,r2,r3','SHR r1,r2,31',
                     'SETM r1','TMC r1','PUSHM','POPM','BARRIER','PRESENT',
                     'WSPAWN r1, -1','BRANY -8192','.word 0xffffffff']:
            with self.subTest(text=text):self.assertEqual(len(assemble(text)),1)

if __name__=='__main__': unittest.main()
