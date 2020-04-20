# cython: language_level=3
from cpython.mem cimport PyMem_Malloc, PyMem_Free


cdef class Buffer:

    def __cinit__(self, size_t capacity):
        self.data = <unsigned char*> PyMem_Malloc(
            sizeof(unsigned char) * capacity
        )
        if not self.data:
            raise MemoryError("Cannot allocate out buffer")

    def __dealloc__(self):
        PyMem_Free(self.data)

    def __init__(self, size_t capacity):
        self.size = 0
        self.capacity = capacity
