/* atoi example */
#include <stdio.h>      /* printf, fgets */
#include <CreateM:
#include <string>
#include <unordered_set>
#include <stdlib.h>     /* atoi */

int main ()
{
  int i;
  char buffer[256];
  printf ("Enter a number: ");
  fgets (buffer, 256, stdin);
  i = atoi (buffer);
  printf ("The value entered is %d. Its double is %d.\n",i,i*2);
  return 0;
}

int main ()
{
  std::unordered_set<std::string> myset;

  myset.emplace ("potatoes");
  myset.emplace ("milk");
  myset.emplace ("flour");

  std::cout << "myset contains:";
  for (const std::string& x: myset) std::cout << " " << x;

  std::cout << std::endl;
  return 0;
}
