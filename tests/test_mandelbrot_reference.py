import unittest
from model.mandelbrot_reference import escape_iterations, multiply, render, color

class MandelbrotTests(unittest.TestCase):
    def test_known_points(self):
        for bits in (13,16):
            scale=1<<bits
            self.assertEqual(escape_iterations(0,0,64,bits),64)
            self.assertEqual(escape_iterations(-scale,0,64,bits),64)
            self.assertEqual(escape_iterations(3*scale,0,64,bits),1)
        self.assertEqual(escape_iterations(2*(1<<16),0,64,16),2)
        # Q13 C-style int32 multiplication overflows after z overshoots to 6.
        self.assertEqual(escape_iterations(2*(1<<13),0,64,13),64)
    def test_q16_multiply(self):
        self.assertEqual(multiply(-98304,131072),-196608)
        self.assertEqual(multiply(-1,32768),-1)
        self.assertEqual(multiply(0x40000000,0x40000),0)
    def test_view_and_palette(self):
        frame=render(target='neck',bits=13)
        self.assertEqual(frame['x_start'],-6144-1536*8)
        self.assertEqual(len(frame['pixels']),256)
        self.assertEqual(color(128,128),0)
        self.assertEqual(color(1,128),0x08050d)
        self.assertEqual(frame,render(target='neck',bits=13))
    def test_zoom_and_validation(self):
        self.assertLess(render(step=16)['x_step'],render(step=0)['x_step'])
        with self.assertRaises(ValueError):render(width=0)
        with self.assertRaises(ValueError):render(max_iter=63)
