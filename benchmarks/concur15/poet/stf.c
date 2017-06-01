/* adapted from https://svn.sosy-lab.org/software/sv-benchmarks/trunk/c/pthread/stateful01_true-unreach-call.c */
#include "pthread.h"

pthread_mutex_t  ma, mb;
int data1, data2;

void * thread1(void * arg)
{ 
  pthread_mutex_lock(ma);
  data1++;
  pthread_mutex_unlock(ma);

  pthread_mutex_lock(ma);
  data2++;
  pthread_mutex_unlock(ma);
}


void * thread2(void * arg)
{ 
  pthread_mutex_lock(ma);
  data1+=5;
  pthread_mutex_unlock(ma);

  pthread_mutex_lock(ma);
  data2-=6;
  pthread_mutex_unlock(ma);
}


int main()
{
  pthread_t  t1, t2;

  pthread_mutex_init(ma, NULL);
  pthread_mutex_init(mb, NULL);

  data1 = 10;
  data2 = 10;

  pthread_create(t1, NULL, thread1, NULL);
  pthread_create(t2, NULL, thread2, NULL);
  
  pthread_join(t1, NULL);
  pthread_join(t2, NULL);
  int aux=data1;
  if (aux!=16 && data2!=5)
  {
    __VERIFIER_error();
  }
}

