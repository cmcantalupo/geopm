#include <iostream>
#include <unistd.h>
#include <vector>

int main(int argc, char **argv)
{
   int start_pid = getpid();
   std::cout << "PID=" << start_pid << " main\n";
   int fork_pid = fork();

   if (fork_pid == 0) {
       std::cout << "PID=" << getpid() << " fork\n";
       execv("/usr/bin/cat", argv);
   }
   std::cout << "PID=" << fork_pid << " forked\n";
   return 0;
}
