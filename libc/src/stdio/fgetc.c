/*
 * fgetc.c
 */

#include "stdioint.h"

int fgetc_simple(FILE *file)
{
	unsigned char ch;
   return _fread(&ch, 1, file) == 1 ? ch : EOF;
}

int fgetc_orig(FILE *file)
{
	struct _IO_file_pvt *f = stdio_pvt(file);
	unsigned char ch;

	if (__likely(f->ibytes)) {
		f->ibytes--;
		return (unsigned char) *f->data++;
	} else {
		return _fread(&ch, 1, file) == 1 ? ch : EOF;
	}
}

int fgetc(FILE *file)
{
#ifdef KLIBC_STREAMS_ORIG
   return fgetc_orig (file);
#else
   return fgetc_simple (file);
#endif
}
