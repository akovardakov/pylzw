# cython: language_level=3
from cpython.mem cimport PyMem_Malloc, PyMem_Realloc, PyMem_Free
from libc.string cimport memcpy
from pylzw.buffer cimport Buffer

# TODO: Move consts to separate file
cdef unsigned char DEFAULT_MIN_BITS = 9
cdef unsigned char DEFAULT_MAX_BITS = 12

cdef unsigned int CLEAR_CODE = 256
cdef unsigned int END_OF_INFO_CODE = 257
cdef size_t INITIAL_CODE_SIZE = 258
cdef size_t MAX_CODE_SIZE = (1 << DEFAULT_MAX_BITS) - 1

cdef size_t BUFFER_SIZE = 0xFFFFFF * sizeof(unsigned char)


cdef class BitPacker:

    cdef Buffer buf
    cdef unsigned char byte
    cdef unsigned char index
    cdef unsigned char point_width
    cdef size_t max_value
    cdef size_t code_size

    def __init__(self, size_t size):
        self.buf = Buffer(size)
        self.byte = 0
        self.index = 0
        self.clear()

    cdef void write(self, unsigned int codepoint):
        cdef unsigned char i
        if codepoint == END_OF_INFO_CODE:
            if self.code_size < MAX_CODE_SIZE - 1:
                if self.code_size >= self.max_value:
                    self.point_width += 1
        for i in range(self.point_width-1, -1, -1):
            if (codepoint & (1 << i)):
                self.byte |= (0x80 >> self.index)
            self.index += 1
            if self.index == 8:
                self.buf.write_byte(self.byte)
                self.index = 0
                self.byte = 0
        self.code_size += 1
        while self.code_size >= self.max_value:
            self.point_width += 1
            self.max_value = 1 << self.point_width

    cdef void clear(self):
        self.point_width = DEFAULT_MIN_BITS
        self.max_value = 1 << self.point_width
        self.code_size = INITIAL_CODE_SIZE

    cdef bytes value(self):
        if self.index > 0:
            self.buf.write_byte(self.byte)
            self.index = 0
        return self.buf.value()


cdef struct Node:
    Node * left
    Node * right
    unsigned char byte
    short cp


cdef class EncodeDict:
    cdef size_t code_size
    cdef Node ** next_byte
    cdef Node * buf

    def __init__(self):
        self.clear()

    def __cinit__(self):
        self.next_byte = <Node ** > PyMem_Malloc(
            sizeof(Node * ) * MAX_CODE_SIZE
        )
        if not self.next_byte:
            raise MemoryError("Cannot allocate Node")
        self.buf = <Node * > PyMem_Malloc(
            sizeof(Node) * MAX_CODE_SIZE
        )
        if not self.buf:
            raise MemoryError("Cannot allocate Node")

    def __dealloc__(self):
        PyMem_Free(self.next_byte)
        PyMem_Free(self.buf)

    cdef void clear(self):
        cdef size_t i
        for i in range(256):
            self.next_byte[i] = NULL
        self.code_size = INITIAL_CODE_SIZE

    cdef void add_cp(self, short last_cp, unsigned char next_byte, Node * next_node):
        self.next_byte[self.code_size] = NULL
        cdef Node * new_node = self.buf + self.code_size
        new_node.left = NULL
        new_node.right = NULL
        new_node.byte = next_byte
        new_node.cp = self.code_size
        if next_node:
            if next_byte < next_node.byte:
                next_node.left = new_node
            else:
                next_node.right = new_node
        else:
            self.next_byte[last_cp] = new_node
        self.code_size += 1

    cdef Node * find_cp(self, short last_cp, unsigned char next_byte):
        cdef Node * n_root = self.next_byte[last_cp]
        cdef Node * root = n_root
        while n_root:
            root = n_root
            if root.byte == next_byte:
                return root
            elif next_byte < root.byte:
                n_root = root.left
            else:
                n_root = root.right
        return root


cdef class Encoder:

    cdef BitPacker bitpacker
    cdef EncodeDict dictionary
    cdef unsigned int max_value
    cdef unsigned short * cp_buffer
    cdef size_t cp_buffer_size

    def __init__(self):
        self.bitpacker = BitPacker(BUFFER_SIZE)
        self.dictionary = EncodeDict()
        self.clear()

    def __cinit__(self):
        self.cp_buffer = <unsigned short*> PyMem_Malloc(
            sizeof(unsigned short) * BUFFER_SIZE
        )
        if not self.cp_buffer:
            raise MemoryError("Cannot allocate out buffer")
        self.cp_buffer_size = 0

    def __dealloc__(self):
        PyMem_Free(self.cp_buffer)

    cdef void clear(self):
        self.bitpacker.clear()
        self.dictionary.clear()
        self.max_value = 1 << self.bitpacker.point_width

    cdef void write_cp(self, unsigned int cp):
        self.bitpacker.write(cp)
        if cp == CLEAR_CODE:
            self.clear()

    cdef bytes compress(self, unsigned char * src, size_t src_len):
        cdef size_t i

        self.write_cp(CLEAR_CODE)

        cdef short cur_cp = src[0]
        cdef Node * next_node
        cdef unsigned char next_byte

        for i in range(1, src_len):
            next_byte = src[i]
            next_node = self.dictionary.find_cp(cur_cp, next_byte)
            if (next_node == NULL) or next_node.byte != next_byte:
                self.bitpacker.write(cur_cp)
                self.dictionary.add_cp(cur_cp, next_byte, next_node)
                if self.dictionary.code_size == MAX_CODE_SIZE:
                    self.write_cp(CLEAR_CODE)
                cur_cp = next_byte
            else:
                cur_cp = next_node.cp

        self.write_cp(cur_cp)
        self.write_cp(END_OF_INFO_CODE)

        return self.bitpacker.value()


def compress(bytes source):
    cdef unsigned char * src = <unsigned char * > source
    cdef size_t src_len = len(source)
    return Encoder().compress(src, src_len)
