# Go Play — Nearby Discovery: Frozen Specification (Wilayat model)

| | |
|---|---|
| **Status** | Ready to freeze — pending Product Owner acknowledgement of the data rules in §2.1–§2.2 |
| **Date** | 2026-09-29 |
| **Nature** | Specification only. No code, no migration, nothing applied. |
| **Supersedes** | `Nearby_Discovery_Independent_Review.md` (same folder) for everything it covers |

---

## 1. Closed product decisions (do not reopen)

1. **Near unit:** Wilayat, and only Wilayat. No Locality entity; villages are search aliases of their Wilayat.
2. **No** GPS, coordinates, maps, geocoding, PostGIS, earthdistance or distance ranking.
3. **Discover:** the three existing tabs (Latest Results · Upcoming Matches · Communities), the current opening tab, no Nearby tab, no Live tab. The only new element is the chip `قريب من: [الولاية]` / `Near: [Wilayat]`.
4. **User location:**
   - `default_wilayat_code` on the account, optional, private to the owner, and changed only by an explicit profile action.
   - The explicit action is Edit Profile: the Default Location is **saved immediately when selected**, and the user can **clear** it later. *(Product Owner decision, 2026-09-29.)*
   - Near starts from the Default Location. A change of Near overrides it for the current session only.
   - Guests store their choice locally on the device.
5. **Community location:**
   - `communities.wilayat_code` is required in the app and nullable in the database for backward compatibility.
   - The existing community is assigned **Sohar**; مجيس / Majees is an alias of Sohar.
   - Only the owner can change the Wilayat, through one menu action, one picker and one server operation. There is no general Edit Community.
   - System Admin corrections are made in SQL through the Charter gate.
6. **Match location:** none stored. Match → Community → current Wilayat. `matches.location` remains the display-only venue text. The historical-label effect of a later Wilayat change is accepted for the MVP.
7. **Upcoming Matches:** local group first, then non-local.
   - Within each group, LIVE matches (`start_at <= now < end_at`) come first, followed by not-started matches by `start_at`.
   - Sorting by `start_at` ascending already produces this order; LIVE is a badge only.
   - Ended matches are excluded.
8. **Communities:** local group first, then non-local.
   - **A community with no Wilayat belongs to the non-local group** and is ordered by the same rule as any other non-local community. There is no separate group and no forced last place.
   - Within each group, order by the latest start_at of an ended match. "Ended" means `status = 'completed' OR end_at <= now()`, the same predicate as `v_football_completed_matches` (migration `0057`). A community with no ended match is ordered by its `created_at`.
   - Final tie-breaker: `id`.
9. **Latest Results:** **unchanged, exactly as today.** It publishes only matches with a recorded result: `public_recent_results` (migration `0081`) for guests and the existing football feed for members. "Completed" is not reinterpreted, and the contract is not touched.
10. **Wilayat label:** shown on **Upcoming Matches cards** and **Communities cards** only. Not on Latest Results cards, and not on any other existing card.
11. **Fallback:** local results come first when they exist, otherwise everything else, with no message. No empty screen is caused by location.
12. **No "Other / Not listed" value.** No location is `null`.
13. The existing Feature → Repository → Adapter → Supabase Adapter architecture, state management, routing and Club design system are unchanged.

---

## 2. Reference data: authoritative source and verification

| Item | Finding |
|---|---|
| **Authoritative source** | Ministry of Interior open data, dataset **«محافظات وولايات سلطنة عُمان»** (category «التقسيم الإداري في سلطنة عُمان»), page `https://www.moi.gov.om/ar-om/Page/open-data`, file `محافظات سلطنة عُمان والولايات التابعة لها.xlsx` |
| File provenance | Retrieved 2026-09-29. SHA-256 `feb99264d496dbf9e2ff0e9a9abb8886f02cee06a102aba895fe890ae347def0`. Workbook metadata: created and modified 2022-08-03. The page shows no update date. A copy is kept at `Docs/reviews/sources/`. |
| Columns | `Region Code`, `Region Name`, `Wilayat Code`, `Wilayat Name`, in Arabic only. **No English names.** |
| **Count** | **11 Governorates** (Region Code 1–11) and **63 Wilayats** (Wilayat Code 1–63). Every code in both ranges is present, none is duplicated, and there are no gaps. |
| Cross-check | NCSI *Statistical Year Book 2026*, Issue 54 (PDF created 2026-04-30), tables «المحافظات والولايات / Governorate And Wilayat» on pp. 13–14. It lists **11 Governorates and 63 Wilayats**, and the Governorate→Wilayat membership is **identical** to MOI for all 63. The yearbook cites Royal Decree 114/2011 for the eleven Governorates. |
| English names | Taken from the NCSI 2026 table (pp. 13–14), the only official English source found. MOI has none. |
| Majees / مجيس | Not a Wilayat in either source, as expected. It remains an alias of Sohar, as approved. |

### 2.1 Official codes

- MOI publishes **numeric** `Region Code` and `Wilayat Code` columns. **These are official codes, so no code needs to be invented.**
- The codes are ordered by history, not by Governorate: Ar Rustaq = 8 sits under South Batinah, and 61, 62 and 63 sit under three different Governorates. This indicates the codes were kept and appended to rather than renumbered.
- **MOI publishes no written stability guarantee.**
- **NCSI numbers Governorates differently** (1 Muscat, 2 Dhofar, 3 Musandam…) and has no Wilayat codes. Its numbers are display order, not identifiers. **Only the MOI codes are identifiers.**

**Recommendation:**
- Use the MOI codes as the keys: `governorates.code smallint` = MOI Region Code, and `wilayats.code smallint` = MOI Wilayat Code. `communities.wilayat_code` and `users.default_wilayat_code` are `smallint` foreign keys, so **Sohar = 7**.
- This replaces the earlier "stable text code" preference, because an official code exists.
- Once seeded, the keys are Go Play's and are never changed. The migration comment records the source, file hash and retrieval date. If MOI ever renumbers, Go Play keeps its own keys.
- Codes are never shown in the UI.

### 2.2 Naming discrepancies that affect the seed

| Discrepancy | Source evidence | Seed rule (recommended) |
|---|---|---|
| Tatweel (ـ) inside 6 Wilayat names (مسـقط، السـيب، مـطرح، بوشـر، العامـرات، ثـمـريت) | MOI file | Strip the tatweel. The name is otherwise unchanged. |
| «الباطنه» and «الشرقيه» written with ه | MOI Region Name | Write ة: «شمال الباطنة»، «جنوب الباطنة»، «جنوب الشرقية», matching NCSI. |
| **«محافظة الدخلية»**, a misspelling | MOI Region Name | **«الداخلية»**, matching NCSI. |
| «الجبل الاخضر» without hamza | MOI | «الجبل الأخضر», matching NCSI. |
| Hamza variants (أدم / ادم، إزكي / ازكي، إبراء / ابراء) | MOI has hamza; NCSI does not | Keep the MOI spelling. Picker search normalises hamza, taa marbuta and tatweel so either spelling finds the Wilayat. |
| Governorate prefix «محافظة» | MOI | Store the bare name. The UI adds the prefix if it needs one. |
| English inconsistencies inside NCSI: Sadh vs Sadah, Jaalan Bani Bu Hasan vs Hassan, Al Musanaah vs Al Musanah | NCSI table vs narrative | Use the **table** spelling as the label. Common variants (Seeb, Suwaiq, Khabourah, Jebel Akhdar, Musannah…) are optional search aliases. |

None of these changes the membership or the count; they are orthography only. The raw MOI spelling is kept in the appendix so any normalisation can be traced back.

---

## 3. Minimal data model

| Object | Fields |
|---|---|
| `governorates` | `code smallint PK` (MOI Region Code), `name_ar`, `name_en`, `sort_order` |
| `wilayats` | `code smallint PK` (MOI Wilayat Code), `governorate_code FK`, `name_ar`, `name_en`, `search_terms text[]`, `sort_order`, `is_active` |
| `communities` | `+ wilayat_code smallint FK NULL`; the existing community is set to `7` |
| `users` | `+ default_wilayat_code smallint FK NULL`, private |
| `matches` | no change |
| Guest | local `shared_preferences` key holding the Wilayat code; an inactive or unknown code is treated as `null` |
| Initial alias | Sohar (7): `مجيس`, `Majees` |

---

## 4. Implementation traps (carried from the gate review; technical, not product)

1. **`create_community`:** replace the 3-argument function with one whose Wilayat parameter has `DEFAULT NULL`. Adding it as an overload leaves the API unable to choose between the two, and installed app builds would stop creating communities.
2. **`users` privacy:** do not add `default_wilayat_code` to the column-level SELECT grant. The row policy exposes all active users to any signed-in user. Read it through the user's own profile path, and grant UPDATE on this column for the user's own row.
3. **Reference tables:** enable RLS, allow public read only, and revoke write privileges explicitly (Supabase's default grants would otherwise allow them).
4. **`set_community_wilayat`:** owner only, with the account and community suspension guards from `0064` and `0065`, and it rejects inactive codes. Model it on the join-policy setter.
5. **Public views:** add `wilayat_code` at the end of `v_public_upcoming_matches`, and `wilayat_code` plus `last_activity_at` at the end of `v_public_communities`. Do not touch `public_recent_results` or the football feeds.
6. **Signup:** if the optional picker stays in the signup form, the account-creation trigger (`handle_new_user`, migration `0092`) must ignore an invalid code rather than fail the signup. *Recommended:* offer it right after signup or in Profile instead. The behaviour is unchanged.
7. **Testing:**
   - Put the ordering in a pure Dart function in `DiscoverRepository` and unit-test it with fakes.
   - Add widget tests for the chip, the session override and the guest choice, plus SQL static migration tests.
   - Seed no location fixtures in the shared staging/production project; the existing integration suite already targets it.

---

## 5. Appendix A: Governorates (MOI codes)

| MOI Region Code | Arabic (normalised) | English (NCSI 2026) | MOI raw spelling |
|---|---|---|---|
| 1 | مسقط | Muscat | محافظة مسقط |
| 2 | شمال الباطنة | Al Batinah North | محافظة شمال الباطنه |
| 3 | مسندم | Musandam | محافظة مسندم |
| 4 | البريمي | Al Buraymi | محافظة البريمي |
| 5 | الظاهرة | Adh Dhahirah | محافظة الظاهرة |
| 6 | الداخلية | Ad Dakhiliyah | محافظة الدخلية |
| 7 | شمال الشرقية | Ash Sharqiyah North | محافظة شمال الشرقية |
| 8 | الوسطى | Al Wusta | محافظة الوسطى |
| 9 | ظفار | Dhofar | محافظة ظفار |
| 10 | جنوب الباطنة | Al Batinah South | محافظة جنوب الباطنه |
| 11 | جنوب الشرقية | Ash Sharqiyah South | محافظة جنوب الشرقيه |

## 6. Appendix B: Wilayats (MOI codes, 63 rows)

| MOI Wilayat Code | MOI Region Code | Arabic (normalised) | English (NCSI 2026) | MOI raw spelling (if different) |
|---|---|---|---|---|
| 1 | 1 | مسقط | Muscat | مسـقط |
| 2 | 1 | السيب | As Seeb | السـيب |
| 3 | 1 | مطرح | Mutrah | مـطرح |
| 4 | 1 | بوشر | Bawshar | بوشـر |
| 5 | 1 | العامرات | Al Amrat | العامـرات |
| 6 | 1 | قريات | Qurayyat |  |
| 7 | 2 | صحار | Sohar |  |
| 9 | 2 | شناص | Shinas |  |
| 10 | 2 | لوى | Liwa |  |
| 11 | 2 | صحم | Saham |  |
| 12 | 2 | الخابورة | Al Khaburah |  |
| 13 | 2 | السويق | As Suwayq |  |
| 19 | 3 | خصب | Khasab |  |
| 20 | 3 | بخاء | Bukha |  |
| 21 | 3 | دبا | Daba |  |
| 22 | 3 | مدحاء | Madha |  |
| 23 | 4 | البريمي | Al Buraymi |  |
| 25 | 4 | محضة | Mahdah |  |
| 61 | 4 | السنينة | Al Sinainah |  |
| 24 | 5 | عبري | Ibri |  |
| 26 | 5 | ينقل | Yanqul |  |
| 27 | 5 | ضنك | Dank |  |
| 28 | 6 | نزوى | Nizwa |  |
| 29 | 6 | سمائل | Samail |  |
| 30 | 6 | بهلاء | Bahla |  |
| 31 | 6 | أدم | Adam |  |
| 32 | 6 | الحمراء | Al Hamra |  |
| 33 | 6 | منح | Manah |  |
| 34 | 6 | إزكي | Izki |  |
| 35 | 6 | بدبد | Bid Bid |  |
| 62 | 6 | الجبل الأخضر | Jabal Al-Akhdhar | الجبل الاخضر |
| 37 | 7 | إبراء | Ibra |  |
| 38 | 7 | بدية | Bidiyah |  |
| 39 | 7 | القابل | Al Qabil |  |
| 40 | 7 | المضيبي | Al Mudaybi |  |
| 41 | 7 | دماء والطائيين | Dima Wa At Taiyyin |  |
| 45 | 7 | وادي بني خالد | Wadi Bani Khalid |  |
| 63 | 7 | سناو | Sinaw |  |
| 47 | 8 | هيماء | Hayma |  |
| 48 | 8 | محوت | Muhut |  |
| 49 | 8 | الدقم | Ad Duqm |  |
| 50 | 8 | الجازر | Al Jazer |  |
| 51 | 9 | صلالة | Salalah |  |
| 52 | 9 | ثمريت | Thumrayt | ثـمـريت |
| 53 | 9 | طاقة | Taqah |  |
| 54 | 9 | مرباط | Mirbat |  |
| 55 | 9 | سدح | Sadh |  |
| 56 | 9 | رخيوت | Rakhyut |  |
| 57 | 9 | ضلكوت | Dalkut |  |
| 58 | 9 | مقشن | Muqshin |  |
| 59 | 9 | شليم وجزر الحلانيات | Shalim Wa Juzur Al Hallaniyat |  |
| 60 | 9 | المزيونة | Al Mazuna |  |
| 8 | 10 | الرستاق | Ar Rustaq |  |
| 14 | 10 | نخل | Nakhal |  |
| 15 | 10 | وادي المعاول | Wadi Al Maawil |  |
| 16 | 10 | العوابي | Al Awabi |  |
| 17 | 10 | المصنعة | Al Musanaah |  |
| 18 | 10 | بركاء | Barka |  |
| 36 | 11 | صور | Sur |  |
| 42 | 11 | الكامل والوافي | Al Kamil Wa Al Wafi |  |
| 43 | 11 | جعلان بني بو علي | Jaalan Bani Bu Ali |  |
| 44 | 11 | جعلان بني بو حسن | Jaalan Bani Bu Hasan |  |
| 46 | 11 | مصيرة | Masirah |  |
