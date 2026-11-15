import unittest
from pathlib import Path
from tools.assembler import assemble
from model.gpu_model import GPUModel
from model.mandelbrot_reference import render
from tools.run_mandelbrot import generate_kernel

class MandelbrotKernelTests(unittest.TestCase):
    def test_resolution_generation(self):
        for width,height in [(16,16),(128,128),(320,240)]:
            source=generate_kernel(width,height)
            self.assertNotIn('@',source)
            self.assertEqual(len(assemble(source)),87)
        with self.assertRaises(ValueError):generate_kernel(17,17)

    def test_pixels_and_iterations(self):
        root=Path(__file__).resolve().parents[1]
        words=assemble(generate_kernel(16,16))
        for target,step in [('seahorse',0),('neck',0),('seahorse',12)]:
            with self.subTest(target=target,step=step):
                frame=render(target=target,step=step,max_iter=128)
                m=GPUModel(words,data_depth=512)
                args=[frame[k] for k in ['x_start','y_start','x_step','y_step']]
                for w in range(4):m.launch(w,args=args)
                m.run()
                self.assertEqual(m.memory,frame['pixels']+frame['iterations'])
