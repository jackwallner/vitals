import os, sys
BASE="fastlane/metadata"
# locale: (terms to remove, terms to add). Removals are that locale's "pacing"
# jargon unless noted; adds are SERP-verified in that storefront.
EDITS = {
 "en-US":   ([], ["lb"]),
 "en-AU":   (["pacing"], ["macro"]),
 "en-CA":   (["pacing"], ["macro"]),
 "en-GB":   (["pacing"], ["macro"]),
 "ar-SA":   (["إيقاع"], ["ماكروز"]),
 "ca":      (["ritme"], ["macros"]),
 "cs":      (["tempo"], ["makra"]),
 "da":      (["takt"], ["makroer"]),
 "de-DE":   (["stoffwechsel"], ["makros"]),
 "el":      (["ρυθμός"], ["πρωτεΐνη"]),
 "es-ES":   (["tasametabólica"], ["macros"]),
 "es-MX":   (["tasametabólica"], ["macros"]),
 "fi":      (["tahti"], ["makrot"]),
 "he":      (["קצב"], ["מאקרו"]),
 "hr":      (["ritam", "hodanje"], ["proteini"]),
 "hu":      (["tempó"], ["makrók"]),
 "id":      (["ritme", "gerak"], ["protein"]),
 "it":      (["ritmo"], ["macro"]),
 "kn-IN":   (["ವೇಗ"], ["macro"]),
 "ml-IN":   (["വേഗത"], ["macro"]),
 "ms":      (["ritma", "gerak"], ["protein"]),
 "nl-NL":   (["stofwisseling"], ["macros"]),
 "no":      (["takt", "gang"], ["makroer"]),
 "pl":      (["rytm", "ruch"], ["białko"]),
 "ro":      (["ritm", "mers"], ["proteine"]),
 "ru":      (["темп"], ["бжу"]),
 "sk":      (["tempo"], ["makrá"]),
 "sl-SI":   (["tempo"], ["proteini"]),
 "sv":      (["takt"], ["makros"]),
 "ta-IN":   (["வேகம்"], ["macro"]),
 "te-IN":   (["వేగం"], ["macro"]),
 "tr":      (["tempo", "hareket"], ["protein"]),
 "uk":      (["темп", "рух"], ["макроси"]),
 "vi":      (["nhịp"], ["protein"]),
}
apply = "--apply" in sys.argv
problems=[]
for loc,(remove,add) in sorted(EDITS.items()):
    path=os.path.join(BASE,loc,"keywords.txt")
    if not os.path.exists(path):
        problems.append(f"{loc}: no keywords.txt"); continue
    cur=open(path).read().strip()
    terms=[t for t in cur.split(",") if t]
    for r in remove:
        if r not in terms:
            problems.append(f"{loc}: '{r}' not present to remove")
        else:
            terms.remove(r)
    for a in add:
        if a in terms:
            problems.append(f"{loc}: '{a}' already present")
        else:
            terms.append(a)
    new=",".join(terms)
    flag=""
    if len(new)>100:
        problems.append(f"{loc}: {len(new)} chars OVER LIMIT -> {new}"); flag=" !!"
    if len(terms)!=len(set(terms)):
        problems.append(f"{loc}: duplicate terms")
    print(f"{loc:8} {len(cur):3}->{len(new):3}{flag}  {new}")
    if apply and len(new)<=100:
        open(path,"w").write(new)
print()
if problems:
    print("PROBLEMS:")
    for p in problems: print(" -", p)
else:
    print("all clean")
