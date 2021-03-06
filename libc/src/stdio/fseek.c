/*
 * fseek.c
 */

#include "stdioint.h"

__extern int fseek_simple(FILE *file, off_t where, int whence)
{
	return lseek(file->_IO_fileno, where, whence);
}

__extern int fseek_orig(FILE *file, off_t where, int whence)
{
	struct _IO_file_pvt *f = stdio_pvt(file);
	off_t rv;

	if (f->obytes)
		if (__fflush(f))
			return -1;

	if (whence == SEEK_CUR)
		where -= f->ibytes;

	rv = lseek(f->pub._IO_fileno, where, whence);
	if (__likely(rv >= 0)) {
		f->pub._IO_eof = false;
		f->ibytes = 0;
		return 0;
	} else {
		f->pub._IO_error = true;
		return -1;
	}
}

__extern int fseek(FILE *file, off_t where, int whence)
{
#ifdef KLIBC_STREAMS_ORIG
   return fseek_orig (file, where, whence);
#else
   return fseek_simple (file, where, whence);
#endif
}
