# 00-endpoints — the two ends of the band

`product.xyz` is the **33-atom** Diels-Alder cycloadduct minimum (GFN2 -56.913775 Eh) and is the
band input.  `ts_guess.xyz` is the delivered Diels-Alder saddle (-56.834192 Eh) and is the band's
`--lts-product`.  `reactant.xyz` (the separated fragments, -56.821809 Eh) is kept for reference
only: the full `reactant -> product` band does **not** converge (see
`examples/ts/ts-02-band-family`), because the fragments start 12.6 A apart and coplanar.

No run happens in this folder.
