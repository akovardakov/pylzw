# cython: language_level=3
from cpython.mem cimport PyMem_Malloc, PyMem_Realloc, PyMem_Free
from libc.string cimport memcpy
from pylzw.buffer cimport Buffer

cdef unsigned char DEFAULT_MIN_BITS = 9
cdef unsigned char DEFAULT_MAX_BITS = 12

cdef size_t INITIAL_DICT_BUF_SIZE = 256
cdef unsigned int CLEAR_CODE = 256
cdef unsigned int END_OF_INFO_CODE = 257
cdef size_t INITIAL_CODE_SIZE = 258
cdef size_t MAX_CODE_SIZE = (1 << DEFAULT_MAX_BITS) - 1
cdef size_t MAX_DICT_SIZE = sum(i for i in range(MAX_CODE_SIZE))

# Buffer size of approximately 1.5 mb should be enough for most of files
cdef size_t BUFFER_SIZE = 0xFFFFFF * sizeof(unsigned char)


class EndOfInfo(Exception):
    pass


class DecodeError(Exception):
    def __init__(self, cp, pos, max_value):
        msg = "Cannot decode {} at {}, max value is {}"
        super().__init__(msg.format(cp, pos, max_value))


cdef class DecodeDict:

    cdef unsigned char ** offs
    cdef size_t * size
    cdef Buffer buf
    cdef size_t code_size

    def __cinit__(self):
        self.offs = <unsigned char**> PyMem_Malloc(
            sizeof(unsigned char*) * MAX_CODE_SIZE
        )
        if not self.offs:
            raise MemoryError("Dictionary offsets")

        self.size = <size_t*> PyMem_Malloc(
            sizeof(size_t) * MAX_CODE_SIZE
        )
        if not self.size:
            raise MemoryError("Dictionary sizes")

    def __dealloc__(self):
        PyMem_Free(self.offs)
        PyMem_Free(self.size)

    def __init__(self):
        self.buf = Buffer(MAX_DICT_SIZE)
        cdef size_t i
        for i in range(INITIAL_DICT_BUF_SIZE):
            self.buf.data[i] = <unsigned char> i
            self.offs[i] = self.buf.data + i
            self.size[i] = 1
        self.clear()

    cdef void clear(self):
        self.buf.size = INITIAL_DICT_BUF_SIZE
        self.code_size = INITIAL_CODE_SIZE

    cdef void add(self, size_t last_cp, unsigned char* addr_entry):
        self.offs[self.code_size] = self.buf.data + self.buf.size
        self.size[self.code_size] = self.size[last_cp] + 1

        self.buf.write(self.offs[last_cp], self.size[last_cp])
        self.buf.write(addr_entry, 1)

        self.code_size += 1


cdef class Decoder:

    cdef DecodeDict dictionary
    cdef Buffer buf
    cdef unsigned char point_width
    cdef size_t max_value
    cdef unsigned char* entry
    cdef unsigned int last_cp

    def __init__(self, Buffer buf=None):
        if buf is None:
            self.buf = Buffer(BUFFER_SIZE)
        else:
            self.buf = buf
        self.dictionary = DecodeDict()
        self.clear()

    cdef void clear(self):
        self.dictionary.clear()
        self.point_width = DEFAULT_MIN_BITS
        self.max_value = 1 << self.point_width
        self.last_cp = MAX_CODE_SIZE

    cdef int decode_codepoint(self, unsigned int codepoint):
        if codepoint == CLEAR_CODE:
            self.clear()
            return 0
        elif codepoint == END_OF_INFO_CODE:
            return -1
        elif codepoint == self.dictionary.code_size:
            self.entry = self.dictionary.offs[self.last_cp]
            self.buf.write(self.entry, self.dictionary.size[self.last_cp])
            self.buf.write(self.entry, 1)
        else:
            self.entry = self.dictionary.offs[codepoint]
            self.buf.write(self.entry, self.dictionary.size[codepoint])
        if self.last_cp < MAX_CODE_SIZE:
            self.dictionary.add(self.last_cp, self.entry)
            while self.dictionary.code_size >= self.max_value - 1:
                self.point_width += 1
                self.max_value = 1 << self.point_width
        self.last_cp = codepoint
        return 1

    cdef bytes decompress(self, unsigned char* src, size_t src_len):

        cdef unsigned int i, j
        cdef unsigned char bit_index = 0

        cdef unsigned int codepoint = 0

        for i in range(src_len):
            for j in range(8):

                codepoint <<= 1
                if (0x80 >> j) & src[i]:
                    codepoint |= 1
                bit_index += 1

                if bit_index == self.point_width:
                    if codepoint > self.dictionary.code_size:
                        # It is error, however it rarely happens 
                        # in the end of the buffer
                        if (codepoint >> 1) == END_OF_INFO_CODE:
                            if i == src_len - 1:
                                break
                        raise DecodeError(codepoint,
                                          i,
                                          self.dictionary.code_size)
                    else:
                        if self.decode_codepoint(codepoint) == -1:
                            break
                    bit_index = 0
                    codepoint = 0
            else:
                continue
            break

        return self.buf.value()


def decompress(bytes source):
    cdef unsigned char * src = <unsigned char*> source
    cdef size_t src_len = len(source)
    return Decoder().decompress(src, src_len)
