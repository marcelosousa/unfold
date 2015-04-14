#include "pthread.h" 

const int N = 64; 
int d = 0; 

pthread_mutex_t l1; 

void *thr1()
{
  int i =0; 
  while (i < N)
    {
      // lock 
      pthread_mutex_lock(l1); 
      d = d + i;
      //unlock
      pthread_mutex_unlock(l1); 
      i = i + 5;
    }

}

void *thr2()
{
  int j =0; 
  while (j < N){
    
    // lock 
    pthread_mutex_lock(l1); 
    d = d - j;
    //unlock 
    pthread_mutex_unlock(l1); 
    j = j + 2; 
  }
}


int main()
{
  pthread_t t1, t2; 

  pthread_mutex_init(l1, NULL); 
  
  pthread_create(t1, NULL, thr1, NULL);
  pthread_create(t2, NULL, thr2, NULL);

  pthread_join(t1, NULL);

  pthread_join(t2, NULL);
  
  //return 0;

}