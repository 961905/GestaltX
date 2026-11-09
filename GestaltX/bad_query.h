#ifndef bad_query_h
#define bad_query_h
#include <stdint.h>
#include <stdbool.h>
#include <Foundation/Foundation.h>
int64_t bad_query(const char *path, bool create);
void bad_query_release(int64_t handle);
NSArray<NSString *> *bad_query_list_children(NSString *path, int64_t *status);
#endif
