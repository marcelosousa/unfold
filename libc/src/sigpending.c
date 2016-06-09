/*
 * sigpending.c
 */

#include <signal.h>
#include <sys/syscall.h>
#include <klibc/sysconfig.h>

// Cesar: sigpending is a system call (glibc has it)
#if 0
#if _KLIBC_USE_RT_SIG

__extern int __rt_sigpending(sigset_t *, size_t);

int sigpending(sigset_t * set)
{
	return __rt_sigpending(set, sizeof(sigset_t));
}

#endif
#endif
