// Fixture data for the Go Play UI kit. Shapes follow the Supabase read models
// (matches, communities, community_members, match_registrations, match_results).
window.GP_DATA = {
  me: { name: 'Yousuf Fadhil', position: 'Midfielder', rating: '5.0', form: [3.8, 4.1, 4.0, 4.6, 4.4, 5.0] },
  communities: [
    { id: 'c1', name: 'Al Shamal', description: 'Thursday and Sunday games in the north',
      members: 24, upcoming: 2, played: 18, role: 'Admin', code: '481 902', joinPolicy: 'Open join' },
    { id: 'c2', name: 'Al Bahar', description: 'Small-sided group', members: 9, upcoming: 1, played: 6,
      role: 'Player', codeRequired: true, joinPolicy: 'Join by code' },
  ],
  matches: [
    { id: 'm1', title: 'Thursday practice', community: 'Al Shamal', location: 'Al Shamal 6-a-side',
      wd: 'Thu', d: 13, mo: 'Aug', time: '17:25 – 18:35', starting: 12, reserve: 6, registered: 6,
      status: 'open', joined: true, role: 'Admin', next: true, inHours: 4 },
    { id: 'm2', title: 'Friday five-a-side', community: 'Al Bahar', location: 'Marina courts',
      wd: 'Fri', d: 14, mo: 'Aug', time: '19:00 – 20:30', starting: 10, reserve: 6, registered: 10,
      status: 'full', joined: false, role: 'Player' },
    { id: 'm3', title: 'Sunday league', community: 'Al Shamal', location: 'Al Shamal 6-a-side',
      wd: 'Sun', d: 7, mo: 'Aug', time: '17:20 – 18:35', starting: 14, reserve: 6, registered: 14,
      status: 'completed', joined: true, role: 'Admin', score: '3 – 2' },
  ],
  roster: [
    { name: 'Khalid Al Balushi', position: 'Goalkeeper' },
    { name: 'Talib Abu Fahd', position: 'Defender' },
    { name: 'Mohammed Al Sadrani', position: 'Defender' },
    { name: 'Yousuf Fadhil', position: 'Midfielder', you: true },
    { name: 'Omar Al Harthy', position: 'Forward' },
    { name: 'Faisal', guest: true },
  ],
  reserve: [{ name: 'Nasser Al Kaabi', position: 'Forward' }],
  members: [
    { name: 'Khalid Al Balushi', role: 'Owner', position: 'Goalkeeper' },
    { name: 'Yousuf Fadhil', role: 'Admin', position: 'Midfielder', you: true },
    { name: 'Talib Abu Fahd', role: 'Player', position: 'Defender' },
    { name: 'Mohammed Al Sadrani', role: 'Player', position: 'Defender' },
    { name: 'Omar Al Harthy', role: 'Player', position: 'Forward' },
  ],
  teams: {
    a: [{ name: 'Khalid Al Balushi', position: 'Goalkeeper' }, { name: 'Talib Abu Fahd', position: 'Defender' },
        { name: 'Yousuf Fadhil', position: 'Midfielder', you: true }],
    b: [{ name: 'Mohammed Al Sadrani', position: 'Defender' }, { name: 'Omar Al Harthy', position: 'Forward' },
        { name: 'Faisal', guest: true }],
  },
  stats: [
    { icon: 'sports_soccer', value: 3, label: 'Played' },
    { icon: 'trophy', value: 1, label: 'Wins' },
    { icon: 'trending_down', value: 2, label: 'Losses' },
    { icon: 'remove', value: 0, label: 'Draws' },
    { icon: 'scoreboard', value: 2, label: 'Goals' },
    { icon: 'star', value: 0, label: 'MOTM' },
  ],
  notifications: 3,
};

/** Arabic fixtures — deliberately at the long end of what the product allows, so
 *  the RTL pass in the review harness is a truncation test and not a courtesy.
 *  Chrome strings stay English here: the app already ships app_ar.arb, and what
 *  this harness has to prove is that the LAYOUT survives Arabic content. */
window.GP_DATA_AR = (() => {
  const d = JSON.parse(JSON.stringify(window.GP_DATA));
  d.me.name = 'يوسف بن عبدالله الفاضل الحارثي';
  d.me.position = 'خط الوسط';
  d.communities[0].name = 'مجتمع الشمال لكرة القدم';
  d.communities[0].description = 'مباريات كل خميس وأحد في ملاعب الشمال الشمالية';
  d.communities[1].name = 'نادي البحر الرياضي';
  d.communities[1].description = 'مجموعة الملاعب الصغيرة';
  const titles = ['تمرين مساء الخميس الأسبوعي', 'مباراة الجمعة خماسي الأضلاع', 'دوري الأحد الودي'];
  const locs = ['ملعب الشمال السداسي المغطى', 'ملاعب المارينا الرياضية', 'ملعب الشمال السداسي المغطى'];
  d.matches.forEach((m, i) => {
    m.title = titles[i]; m.location = locs[i];
    m.community = i === 1 ? d.communities[1].name : d.communities[0].name;
    m.wd = ['خميس', 'جمعة', 'أحد'][i];
    m.mo = 'أغسطس';
  });
  const names = ['خالد بن سالم البلوشي', 'طالب أبو فهد الكندي', 'محمد بن ناصر الصدراني',
    'يوسف بن عبدالله الفاضل', 'عمر بن حمد الحارثي', 'فيصل'];
  const pos = ['حارس مرمى', 'مدافع', 'مدافع', 'خط الوسط', 'مهاجم', ''];
  d.roster.forEach((p, i) => { p.name = names[i]; if (!p.guest) p.position = pos[i]; });
  d.reserve[0].name = 'ناصر بن جمعة الكعبي'; d.reserve[0].position = 'مهاجم';
  d.members.forEach((m, i) => { m.name = names[i]; m.position = pos[i]; });
  d.teams.a.forEach((p, i) => { p.name = [names[0], names[1], names[3]][i]; if (!p.guest) p.position = [pos[0], pos[1], pos[3]][i]; });
  d.teams.b.forEach((p, i) => { p.name = [names[2], names[4], names[5]][i]; if (!p.guest) p.position = [pos[2], pos[4], ''][i]; });
  d.stats = d.stats.map((s, i) => ({ ...s, label: ['المباريات', 'الانتصارات', 'الخسائر', 'التعادلات', 'الأهداف', 'أفضل لاعب'][i] }));
  return d;
})();

/** The fixture set for the current review direction. */
window.T = (review) => (review && review.dir === 'rtl' ? window.GP_DATA_AR : window.GP_DATA);
