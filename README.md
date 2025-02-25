# moo
moo-lang.. smol, simple

- small executable (under 3mb so far)
- esolang feel
- extensible
- ideosyncratic

# spec so far
```moo
@ <import-filename/with/slashes/and/without.moo ext>
<function> <args ...string/f64/bool>
<label>: <function> <args ...string/f64/bool>
| comments between these up right characters |

str moo "uwu uwu"                     | str is a function and moo is its first argument and the string is its second (this is just a comment) | 
` ~moo `
| see? ^- `these ticks will print out what's between them and template/replace/read from the scope with ~` |

my_struct:
  prop 5.55
  msg "let me, love you, all the... way through"
  subspace: x 3 y 32 z 0 moniker "warra-machine", | the : delimits sub-spaces and is closed by a comma, commas are otherwise not wanted |
;

```
![image](https://github.com/user-attachments/assets/b5b23b06-f1c5-4d4b-9057-1938b905e72c)


install vlang, gcc or clang, as well as the relevant dependencies vlang expects

v -prod moo.v
./moo
