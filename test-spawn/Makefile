all: libinject.so main_fork main_spawn main_forkl main_spawnl

clean:
	rm -f libinject.so main_fork main_spawn main_forkl main_spawnl

libinject.so: libinject.cpp
	g++ -shared -fPIC -o libinject.so libinject.cpp

main_fork: main_fork.cpp
	g++ main_fork.cpp -o main_fork

main_spawn: main_spawn.cpp
	g++ main_spawn.cpp -o main_spawn

main_forkl: main_fork.cpp
	g++ main_fork.cpp libinject_link.cpp -L. -linject -o main_forkl

main_spawnl: main_spawn.cpp
	g++  main_spawn.cpp libinject_link.cpp -L. -Wl,--whole-archive -linject -Wl,--no-whole-archive -o main_spawnl

check: check_fork check_spawn check_forkl check_spawnl


check_fork: libinject.so main_fork
	grep $$(sh -c "LD_LIBRARY_PATH=:$$LD_LIBRARY_PATH LD_PRELOAD=libinject.so ./main_fork /proc/self/status" | grep '^Pid:' | sed -e 's|Pid:||') libinject.log
	rm libinject.log
	echo "PASS: check_fork"

check_spawn: libinject.so main_spawn
	grep $$(sh -c "LD_LIBRARY_PATH=:$$LD_LIBRARY_PATH LD_PRELOAD=libinject.so ./main_spawn /proc/self/status" | grep '^Pid:' | sed -e 's|Pid:||') libinject.log
	rm libinject.log
	echo "PASS: check_spawn"

check_forkl: libinject.so main_forkl
	grep -v $$(sh -c "LD_LIBRARY_PATH=: ./main_forkl /proc/self/status" | grep '^Pid:' | sed -e 's|Pid:||') libinject.log
	rm libinject.log
	echo "PASS: check_forkl"

check_spawnl: libinject.so main_spawnl
	grep -v $$(sh -c "LD_LIBRARY_PATH=: ./main_spawnl /proc/self/status" | grep '^Pid:' | sed -e 's|Pid:||') libinject.log
	rm libinject.log
	echo "PASS: check_spawnl"

