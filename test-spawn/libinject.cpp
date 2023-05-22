#include <iostream>
#include <fstream>
#include <unistd.h>

void libinject_link(void)
{

}

static void __attribute__((constructor)) hello(void)
{
   std::fstream log_file("libinject.log", std::ios::app);
   log_file << "PID=" << getpid() << " init\n";
}


static void __attribute__((destructor)) goodbye(void)
{
   std::fstream log_file("libinject.log", std::ios::app);
   log_file << "PID=" << getpid() << " fini\n";
}

