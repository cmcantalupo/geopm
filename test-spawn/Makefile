all: libinject.so main_fork main_spawn

libinject.so: libinject.cpp
	g++ -shared -fPIC -o libinject.so libinject.cpp

main_fork: main_fork.cpp
	g++ main_fork.cpp -o main_fork

main_spawn: main_spawn.cpp
	g++ main_spawn.cpp -o main_spawn

check: check_fork check_spawn

check_fork:
	grep $$(sh -c "LD_LIBRARY_PATH=:$$LD_LIBRARY_PATH LD_PRELOAD=libinject.so ./main_fork /proc/self/status" | grep '^Pid:' | sed -e 's|Pid:||') libinject.log
	rm libinject.log

check_spawn:
	grep $$(sh -c "LD_LIBRARY_PATH=:$$LD_LIBRARY_PATH LD_PRELOAD=libinject.so ./main_spawn /proc/self/status" | grep '^Pid:' | sed -e 's|Pid:||') libinject.log
	rm libinject.log

