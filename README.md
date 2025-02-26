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


```moo
`hello wurld`

str moo "yes"

`is there moo? ~moo`

box 50 50 40 40 #cccfff


= yes ~moo
? txt "yes yes: control flow" 270 300 24 24 #e9801f



= no no1
! txt "yes no no1: don't match" 260 320 24 24 #e9801f

`yee`

box 150 150 140 70 #da2121

str index "hello my index"

write "./index.txt" ~index

read "./index.txt" index

`here's the score: index.txt reads ~index`
```

![image](https://github.com/user-attachments/assets/6a3b69ea-5f37-4c3a-a90c-65b6a65ab044)


install vlang, gcc or clang, as well as the relevant dependencies vlang expects

v -prod moo.v
./moo
