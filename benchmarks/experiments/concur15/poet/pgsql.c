/* Adapted from PGSQL benchmark from http://link.springer.com/chapter/10.1007%2F978-3-642-37036-6_28 */

/* BOUND 8 */

//#include <stdbool.h>
//#include <assert.h>
#include "pthread.h"

//void __VERIFIER_assume(int);

int latch1 = 1;
int flag1  = 1;
int latch2 = 0;
int flag2  = 0;

int __unbuffered_tmp2 = 0;

void* worker_1()
{
  while(1) {
    // __VERIFIER_assume(latch1);
  L1: if(latch1 != 1) goto L1;
    //assert(!latch1 || flag1);
    if(latch1){
      if(!flag1){
        __poet_fail();
      }
    }

    latch1 = 0;
    if(flag1) {
      flag1 = 0;
      flag2 = 1;
      latch2 = 1;
    }
  }
}

void* worker_2()
{
  while(1) {
    //    __VERIFIER_assume(latch2);
  L2: if(latch2 != 1) goto L2;
    
    //    assert(!latch2 || flag2);
    if(latch2){
      if(!flag2){
        __poet_fail();
      }
    }
    latch2 = 0;
    if(flag2) {
      flag2 = 0;
      flag1 = 1;
      latch1 = 1;
    }
  }
}

int main() {
  pthread_t t1;
  pthread_t t2;
  pthread_create(t1, NULL, worker_1, NULL);
  pthread_create(t2, NULL, worker_2, NULL);
}
