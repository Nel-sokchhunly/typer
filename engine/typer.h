#pragma once
#include <stdint.h>

typedef struct Engine Engine;

Engine *typer_new(const char *data_dir, const char *user_dir);
void typer_free(Engine *e);
char *typer_suggest(const Engine *e, const char *input, uint32_t k);
void typer_pick(Engine *e, const char *input, uint32_t index);
void typer_string_free(char *s);
