# Verification

Scope: native record codec, byte-preserving import/save, typed semantic conversion, bounded diagnostics/repair, and real geometry consumers. No full AutoCAD semantic/interoperability certification is claimed.

## extension-08 (2026-10-28)

Adds one usable record-layer feature: `rewrite_values` validates selected group-code/typed-value preconditions and all existing structural/wire rules before returning a multi-span rewrite plus byte receipts. It preserves the old `rewrite_value` API and all unselected original bytes. `examples/rewrite` runs on JS/Wasm-GC; CLI `tags`, `patch-plan` and `patch` expose inspection, review and separate-file output.

Eight new tests and five affected rewrite regressions run per backend (13 each). They cover out-of-order/length-changing plans, CRLF and legacy bytes, both Binary widths, empty/incomplete plans, bitwise preconditions, wrong/duplicate indices, structural/wire refusals, opaque delimiters and JSON/Int64 precision. Four small independent ezdxf R12/R2018 ASCII/Binary models check 20 edits to geometry, layers, XDATA and XRECORD metadata; source spans are compared byte-for-byte, then actual fields and audit results are checked. CLI invalid plans retain source/existing destination, and input/case/hard-link aliases are rejected for the new patch path.

The separate extension-08 report records the scenario, three candidates, bounded ecosystem review, contract, compatibility/API additions, real command outputs, source/build identities and a new ZIP. Before evidence is the sealed 07 source/API capability, not a claim of a newly discovered old-code defect. Existing unrelated 05–07 checks and large model/precision sweeps are reused. The library buffers input/output and does not claim filesystem-atomic replacement; plans do not insert/delete records, migrate versions or repair references.

## deep-repair-07 (2026-10-28)

Five failing tests established four causes: the simple geometry reader ignored numeric exponents; generic integer parsing silently accepted radix prefixes in values; generic group-code parsing did the same; and failed UTF8 decoding collapsed different legacy block names into one empty key. The fixes transfer exact scalars from published dxfkit typed tags into actual moon-geometry objects, explicitly select decimal parsing, and compare original block-name bytes with ASCII case folding. The upstream parser still supplies entity kinds, defaults and point counts; no geometry algorithms or dependency sources are replaced.

Six new tests cover LINE/CIRCLE/LWPOLYLINE scientific values on ASCII/Binary inputs, finite exponent extremes and signed-zero bits in actual upstream objects, invalid numeric/code prefixes with exact original save and conversion refusal, distinct/equal legacy names, and Julian-date/elapsed-day Double preservation on both wire families. A relevant final pass runs 32 tests per JS/Wasm-GC backend: these six, eight round-06 tests, two exact-integer deep regressions, the legacy-geometry deep regression, eight codec tests, six boundary tests and the original adapter test. The other nine round-05 tests, large historical fixture runs and 142-pattern precision sweep are unchanged and reused.

Pinned ezdxf 1.4.3 independently produces/reads two small time-field files and three CP1252 block-name files; native conversions retain exact values and matching diagnostics. Its tag compiler rejects the three radix-prefix integer cases; the CLI conversion error preserves input and creates no output. Date/header values remain raw DXF Double records: no Unix-time, timezone or date-conversion feature has been added. See Autodesk's [date/time variable meaning](https://help.autodesk.com/cloudhelp/2021/ENU/AutoCAD-DXF/files/GUID-6942BAF3-095F-4217-9F61-6931975D3A64.htm) and [HEADER codes](https://help.autodesk.com/cloudhelp/2021/ENU/AutoCAD-DXF/files/GUID-A85E8E67-27CD-4C59-BE61-4DC9FADBE74A.htm).

The pinned ezdxf full-model loader itself replaces `$TDCREATE` with current time in `_setup_metadata`. All four original time values are therefore independently compared through its raw tag loader and `HeaderSection.load`; full-model loading is recorded separately and the other three values also match there. This dependency behavior is reported, not patched or counted as a product defect.

The separate deep-repair-07-max-20261028 report retains hypotheses, failed tests, initial test-syntax/negative-zero fixture corrections, source/build pins, final commands and a new archive. The probe's negative-zero text is explicit because generic interpolation can erase its sign; this was a fixture correction, not a product defect. Core and adapter public APIs remain unchanged. Earlier reports and archives are preserved.

## deep-repair-06 (2026-10-28)

Nine concrete failing paths were reproduced: a vendor record outside HEADER impersonating ACADVER; a 999 comment becoming the declared version; a commented version value bypassing the edit guard; ASCII block-name case causing a false dangling reference; an oversized malformed ASCII pair bypassing max_tag_bytes in repair; optional LINE Z values leaking between records; LWPOLYLINE points cleared by the upstream parser's shared array; an ENTITIES-name comment hiding all geometry; and Windows case aliases allowing the CLI to overwrite its input. The original bytes and ordinary non-header values remain preserved/editable. The existing positive UTF8 BOM behavior is explicitly retained, not claimed as a fix.

Eight new `round06 *` tests include all two-chunk splits of the malformed budget case, mixed LINE/CIRCLE/LWPOLYLINE coordinate assertions, stable repeated drawing snapshots and later pumping. A clean pass runs these plus the same 27 affected existing tests on each of JS and Wasm-GC (35 per backend). Three unchanged historical large fixture tests and the round-05 precision sweep are reused, not counted as new executions. CLI probes reject case and hard-link aliases with exit 2 and unchanged source SHA256; a distinct output succeeds. Pinned ezdxf 1.4.3 independently checks block resolution, HEADER comments, default Z and polyline points, and audits the native binary block-model output with zero errors/fixes.

The geometry adapter uses the published upstream parser separately per record and its end-of-input flush so that coordinate state and mutable point arrays cannot leak. No dependency source or geometry math is patched. Core public APIs remain unchanged; the adapter has one additional record-buffer field. ASCII case folding is the name-matching behavior exercised here; non-ASCII case-folding and other vendor codepages receive no new acceptance claim.

Sources: Autodesk's [group 999 description](https://images.autodesk.com/adsk/files/autocad_2014_pdf_dxf_reference_enu.pdf) and ezdxf's [block-name semantics](https://ezdxf.readthedocs.io/en/stable/dxfinternals/block_management.html), backed by the pinned installed validator and actual consumers. Before/after source manifests, build artifact hashes, failing logs, final commands, consumer probes and the new ZIP are retained in the separate `deep-repair-06-max-20261028` report. No historical archive is overwritten.

## deep-repair-05 (2026-10-28)

Eight failures were reproduced before their fixes: SECTION/TABLE-name edit bypass, exact scientific integer input rejected, implicit wire-family migration by repair, typed records silently dropped after EOF, stray ENDSEC accepted as a complete section, ignored legacy metadata blocking supported geometry, Opaque edit delimiter injection, and Binary tag-boundary truncation incorrectly repaired by inventing ENDSEC. The fixes preserve ordinary code2/UCS-value edits and raw original bytes.

This round runs 12 new `deep *` tests and 15 affected existing tests on each of JS/Wasm-GC; the three unchanged model-fixture tests are reused from the historical baseline below rather than rerun. New boundary checks enumerate ASCII CRLF/UTF8 two-chunk splits, old/new Binary cuts and midstream consumer errors. An independent Python struct producer plus pinned ezdxf loader checks 142 finite binary64 patterns on both wire families and nine exact Int64 edge values, including magnitudes above 2^53. Its scripts/results and before/after source identities are in the separate deep-repair-05 report directory, not mixed into historical evidence.

Autodesk's [XDATA example](https://help.autodesk.com/cloudhelp/2018/ENU/AutoCAD-DXF/files/GUID-A2A628B0-3699-4740-A215-C560E7242F63.htm) explicitly uses scientific decimal notation for an integer. The new decimal normalization is exact and rejects fractional/out-of-range values, avoiding binary64 rounding near Int64 limits.

The following implementation-03 counts and vendor/data limitations remain historical facts, not new execution totals. New source ZIPs do not overwrite the original delivery.

## Reproduce

Use MoonBit v0.10.17 (2026-10-23) or a compatible newer toolchain. Install the reference tool in an isolated environment, then run:

```sh
python -m venv reference-env
# Activate reference-env, then:
python -m pip install ezdxf==1.4.3
python tools/validate.py /absolute/path/to/moon /absolute/path/to/report-directory
```

The script records each command, exit code, unmodified stdout/stderr, source hashes and an aggregate source identity. It stops on the first unexpected exit. It uses frozen fixture outputs by default; regenerating is explicit:

```sh
python tools/reference.py generate
python tools/generate_fixture_tests.py
```

The generator uses ezdxf's documented/source-verified `write_fixed_meta_data_for_testing` option so ASCII and Binary writes do not differ merely by write timestamps. Its fixture model code is separate from the native decoder. Embedded test byte literals are generated fixtures, not effective implementation LOC.

## Evidence layers

| Evidence | What is actually compared |
| --- | --- |
| 18 tests on JS and Wasm-GC | Complete independent R12/R2000/R2018 models read in chunks of 1/2/7/31/4096 bytes, wire-family profiles, Int64 extrema, signed zero, NaN payload, opaque tail, explicit repair/resource/lifecycle errors, stream-writer errors and actual sink coordinates |
| Independent typed tags | ezdxf low-level binary_tags_loader golden tags: R12 573, R2000 1507, R2018 1639; total 3719. Full ordered code/type/value comparison, integers as decimal strings and Double as signed64 raw bits |
| Byte preservation | The three independently produced Binary files and malformed unknown-tail input compared to exact saved input; one-value edits assert unchanged prefix/suffix |
| Semantic conversion | ASCII→native Binary and Binary→native ASCII both compared to independent tag truth, then six outputs loaded by ezdxf and audited: errors=0 and fixes=0 for these fixtures |
| Real consumers | dxfkit receives 4/5/5 modelspace entities; moon-geometry's limited reader receives 2/3/3 (only its supported types). Dedicated tests inspect LINE coordinates and CIRCLE center/radius |
| Defects | Native code detects all five declared categories; independent ezdxf load/audit signals for duplicate handles, missing EOF, missing ENDSEC and missing block. Its default audit does not flag the unbalanced-XDATA example, so no blanket diagnostic equivalence claim |
| CLI | Success lint/convert/save, explicit repair that retains unresolved defects, exact saved bytes, and invalid-argument exit2; no source overwrite |

## Retained failures and corrections

The external execution report retains first compiler failures, the old compiler's undefined Int32 dependency error, missing core-bundle setup, and API adjustments to current MoonBit Json constructors. A local official toolchain archive was SHA256-checked; it did not replace the shared installation or user PATH.

The first cross-format reference comparison differed in ezdxf metadata write timestamps; fixed metadata generation corrected the oracle fixture, not a product rounding tolerance. The next comparison exposed moon-geometry counting a BLOCKS-local line; our adapter now projects only ENTITIES, without patching that dependency. An ASCII repair boundary test initially counted harmless post-EOF whitespace as discarded; the decoder now retains that whitespace until finish and does not classify it as a bad pair.

The initial final-pass API generation encountered an unbundled wasm standard library in the isolated runtime (including a dependency preferred-target path even with --target js). The missing wasm core bundle was built locally; this is environment setup, not evidence of a product failure or a new product backend acceptance claim. Failures are not overwritten as passing evidence.

## Practical limits

Only the specified examples/backends and fixtures were executed. Native vendor CAD exports were not acquired with verified redistribution rights; the bundled inputs are original independent ezdxf exports under CC0, not native AutoCAD/FreeCAD claims. R10/R14/other intermediate versions receive wire-profile tests; only R12/R2000/R2018 have full independent exported models here. The R13 ambiguity remains explicitly unsupported for semantic conversion.

## deep-repair-12 bounded table-lint correction

A missing ENDTAB before a later TABLE was reproducibly hidden by the old pending-table state. Removing only the first table terminator from the frozen independently generated R2018 ASCII model produced exit0 with no diagnostics before the fix. The linter now reports UnclosedTable at the next TABLE's original byte offset, before tracking that table. The [Autodesk table layout](https://help.autodesk.com/cloudhelp/2023/ENU/AutoCAD-DXF/files/GUID-A66D0ACA-3F43-4B2E-A0C2-2B490C1E5268.htm) defines separate TABLE/ENDTAB and section boundaries; no new public API, rejection of otherwise accepted conversion input, or automatic table repair was added.

Three new focused tests and three affected existing lint tests passed on each of JS and Wasm-GC (six per backend). They cover both wire formats, exact read-only/lossless save, legal consecutive/empty tables, multiple missing boundaries, existing ENDSEC/EOF paths, retained repair diagnostics, and existing defect/APPDATA rules. Check, build, generated public interfaces and formatting were verified; root/adapters/bridge interfaces remained byte-identical. Historical large-model and unrelated suites were not rerun.

Ten CLI commands checked the real R2018 ASCII/Binary original and single-ENDTAB-deletion specimens: valid lint exit0, damaged lint exit1 with exact independently frozen offsets, exact save, explicit repair receipt, and persistent unresolved lint after repair. Independent ezdxf low-level tags confirm that only one table boundary is absent and repair preserves the damaged typed sequence, including float64 bits. Its high-level loader and audit tolerate the ASCII specimen with zero errors/fixes, so that is explicitly not an independent audit rejection claim.

The first consumer comparison incorrectly required repair's raw numeric spelling to remain identical; e.g. 0.0 becomes 0 under the documented normalization contract. The failed assertion and specimens were retained, the oracle was corrected to independent typed values/float64 bits, and 15 already-passed commands were reused without execution. A pre-final formatting mismatch was corrected with the official formatter. The final ledger contains 21 commands in total, not 21 tests. All current-round evidence is in deep-repair-12-max-20261028; no earlier sealed package was replaced.

The codec retains raw bytes and therefore requires O(input) memory. No latency/zero-copy/zero-overhead benchmark is claimed. There are no product tests against private/vendor-only opaque entity internals, no published Mooncakes release and no remote CI or contest acceptance claim. CI configuration is included for future authorized use.

## deep-repair-13 application data in the geometry projection

A legal independently exported LWPOLYLINE with two vertices and a private coordinate in a 102 application group reached the actual moon-geometry consumer as three vertices before the fix (`3 != 2`). ezdxf 1.4.3 exported and read back both complete R2018 ASCII/Binary models with two geometric vertices, retained private payload, and audit errors/fixes zero. The same exported entity record is frozen as the new native regression source. The [Autodesk common entity groups](https://help.autodesk.com/cloudhelp/2023/ENU/AutoCAD-DXF/files/GUID-3610039E-27D1-4E23-B6D3-7E60B22BB5BD.htm) define the contents of a 102 group as application-defined data.

The limited GeometrySink projection now retains 102 markers in its record buffer and removes scoped private fields locally before invoking the upstream parser and exact numeric transfer. Depth is local to each record, including nested/plain/named closes; no persistent field was added to the public sink structure. Core source, generic pump_geometry output, saved original bytes and DxfkitSink's full record payload remain intact. This is not a full APPDATA validator or an upstream dependency patch.

The final implementation passed nine adapter tests per backend on JS and Wasm-GC: three new and six affected existing tests. New assertions inspect actual upstream points/scalars, retained private raw tags in the full sink, and recovery at a subsequent record after an unfinished group. Four final CLI commands checked entity counts and byte-exact saves for the complete independent ASCII/Binary models. CLI exposes entity counts; coordinate assertions are in the native test using the exact exported entity in ASCII and native Binary, not a claimed full-file coordinate API.

The first implementation passed behavior tests but its added state field changed the generated public structure description. That interface gate failed, the intermediate source/interface and logs were preserved, and the implementation moved scope tracking into a local record projection. The resulting code change justified one fresh relevant pass. The final eleven-command ledger is FINAL-COMMANDS.json; initial eleven-command results are separately retained and are not folded into final test counts. Root/adapters/bridge generated interfaces are byte-identical to the sealed baseline. Initial producer tuple and required-mode test setup errors are also retained separately, without counting them as product defects. Unchanged core suites and prior sealed scenarios were not rerun.

## deep-repair-14 strict JSON file bytes

The Node file host previously used lossy UTF8 decoding for both request and plan JSON. A byte FF inside a typed text value was silently replaced by U+FFFD: make-plan returned exit0 and emitted the replacement bytes, and patch returned exit0 and wrote a layer name containing the replacement. Python strict UTF8 decoding independently rejected both input files, while ezdxf readback confirmed the incorrectly written layer. These pre-fix files, logs and output are frozen in the round14 report.

A shared host helper now checks the raw buffer with Node's built-in buffer.isUtf8 before the existing bytes.toString('utf8') step. It preserves valid input decoding and BOM treatment, the native JSON numeric lexemes, raw text_hex/binary payloads and DXF source encoding. [RFC 8259 section 8.1](https://www.rfc-editor.org/rfc/rfc8259#section-8.1) provides the interchange encoding basis; the [Node API](https://nodejs.org/api/buffer.html#bufferisutf8input) was added in v19.4.0/v18.14.0, within the existing Node20+ requirement. Actual runtime verification used Node v24.11.0; no Node20 runtime matrix is claimed.

One final relevant pass recorded fifteen commands: one Node syntax check, eight malformed-byte rejections across request formation and both plan formats' preview/write paths (including overlong and incomplete multibyte encodings), and two three-step successful Unicode chains. Failed writes retain existing destinations or leave new destinations absent; sources and JSON inputs remain byte-identical. Valid Chinese, accented text, emoji and explicit U+FFFD are preserved. New outputs match an independent original-record single-span replacement byte for byte, and ezdxf 1.4.3 reads the intended layer and unchanged application payload.

The source drawing and independent model audit are frozen evidence reused from round13; only the new rewritten outputs were independently read back here. MoonBit source and root/adapters/bridge interfaces did not change. Existing JS bridge and JS/Wasm-GC test artifact hashes were verified and reused; no rebuild or native suite rerun is counted as this round's execution. A reproduction console encoding error occurred only after its records and output were saved; it is retained separately and the completed counterexample was not rerun. No global Python encoding setting was changed.

## deep-repair-15 application metadata versus structural edit protection

A valid independently exported LINE carried application-defined code9 text inside a 102 EDITOR_META group. Both source formats loaded and audited in ezdxf 1.4.3 with errors/fixes zero, yet an existing indexed edit plan was rejected as a structural/version migration before the fix. The original error, source files and independent metadata/index/span expectations are frozen in the round15 report.

The structural protection scan now reuses existing APPDATA scope tracking. Every code0 record boundary is locked and resets scope first; private fields neither become HEADER keys nor consume a real TABLE/SECTION name position. Actual HEADER variable keys, version values and section/table names retain their guards. This restores an existing nonstructural edit contract; it adds no public API, APPID-aware lookup or new dependency. Handle-based plan formation still deliberately skips private fields.

The final pass ran three new and eight affected existing rewrite tests on each of JS and Wasm-GC (eleven per backend), including single/batch agreement, nested/private data, actual structural rejection and an unfinished application's next record boundary. Check/build/fmt/info passed and root/adapters/bridge generated interfaces remained byte-identical. Old UTF8 and geometry suites were not rerun.

Twelve CLI commands exercised both ASCII/Binary and legacy/source-bound external plans: four successful previews/writes matched the independent original tag index and raw single-span output bytes; four mixed plans validated metadata before a later prohibited EOF edit and returned exit2 without changing existing destinations or either input. Two distinct successful byte sequences were independently read and audited with expected payload and errors/fixes zero. Identical outputs across plan formats reused that independent readback rather than repeating it. The ledger has twenty-five commands including native tooling, not twenty-five tests.

The report's RESEARCH.md records a bounded Mooncakes/current pinned dxfkit 0.1.1 and ezdxf capability comparison. Existing index/value preconditions suffice for the actual private-metadata task, so no parallel editor or speculative APPID addressing API was added. EXAMPLE.md supplies a runnable source-bound plan example using the frozen legal model. Unsupported whole-document migrations, full application semantics and filesystem atomic replacement remain outside the contract.

## deep-repair-16 explicitly named application targeting

The single scoped capability adds DxfDocument::value_edit_in_appdata and an optional appdata string in make-plan/make-bound-plan requests. A new independent full model has three application groups with repeated codes/values; the requested second direct EDITOR_META code9 previously required a manually indexed plan. CAPABILITY-BEFORE records the old option as intentionally unsupported, not a defect. Research compared the pinned dxfkit record/subclass accessors and ezdxf named application data management before selecting this bounded addition.

Names match exact UTF8 bytes and one unique top-level group. Direct-field occurrence excludes child groups, and missing/ambiguous/unclosed targets or mismatched named closes return an error. The old handle method implementation remains a byte-identical source prefix; it is reused only to resolve the owner record without writing. Default requests continue to skip private fields. Generated plans remain the existing typed index/code/expected/value format and source-bound envelope.

One clean relevant pass ran seven tests per backend on JS and Wasm-GC: five new core/bridge tests and two affected old request-grammar compatibility tests. Core cases cover accurate direct-field occurrence, exact Int64/legacy payload capture, DIMSTYLE ownership and new selector errors. No old UTF8, structural protection or batch refusal suite was rerun. Check/build/fmt/info passed; API diff is exactly one added core method with no old signature removed, and bridge/adapters interfaces are byte-identical.

The MoonBit example ran on both backends. The Node example ran once as the ASCII source-bound chain and preserved its three child command results. Four complete ASCII/Binary and legacy/source-bound chains captured the independently expected target index and original bytes, matched a raw single-span output exactly, and retained the other two application groups. Two distinct byte outputs were read/audited independently with errors/fixes zero; duplicate outputs reused those independent results. Two new CLI lookup error cases produced exit2 with no plan stdout and unchanged input/request bytes.

COMMANDS.json contains twenty-six top-level commands, including the Node wrapper; its child ledger accounts for three CLI actions. There are fourteen actual CLI actions across the four chains and two query failures. This is seven tests per backend and three example runs, not twenty-six tests. Sources/compiled identities and limited unsupported behavior are recorded separately. The new example assets are original CC0 model/request data; no dependency, account, author or remote release was changed.

