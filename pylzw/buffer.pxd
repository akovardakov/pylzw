# cython: language_level=3
from cpython.mem cimport PyMem_Realloc
from libc.string cimport memcpy


cdef class Buffer:

    cdef unsigned char * data
    cdef size_t size
    cdef size_t capacity

    cdef inline void realloc(self, capacity):
        self.data = <unsigned char*> PyMem_Realloc(self.data, capacity)
        if not self.data:
            raise MemoryError("Cannot extend out buffer")
        self.capacity = capacity

    cdef inline void write(self, unsigned char * data, size_t size):
        if self.size + size > self.capacity:
            self.realloc(self.capacity * 2)
        cdef unsigned char * cursor = self.data + self.size
        memcpy(cursor, data, size)
        self.size += size

    cdef inline void write_byte(self, unsigned char byte):
        if self.size == self.capacity:
            self.realloc(self.capacity * 2)
        self.data[self.size] = byte
        self.size += 1

    cdef inline bytes value(self):
        return self.data[:self.size]
