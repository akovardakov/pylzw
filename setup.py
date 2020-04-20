from setuptools import setup, find_packages
from setuptools.extension import Extension

setup(
    name="pylzw",
    version="1.0.0",
    packages=find_packages(),
    ext_modules = [
        Extension("pylzw.encoder", ["pylzw/encoder.c"]),
        Extension("pylzw.decoder", ["pylzw/decoder.c"]),
        Extension("pylzw.buffer", ["pylzw/buffer.c"]),
        ],
    zip_safe=False,
    extra_compile_args=["-O3"],
)
