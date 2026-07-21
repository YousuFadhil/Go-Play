# 06 ERD


ERD Engineering Version (v2) - Football Community Manager

1. Scope

النسخة الهندسية المرجعية لمخطط الكيانات والعلاقات الخاصة بالنظام.

2. Core Entities

Users, Groups, GroupMembers, Fields, Matches, MatchRegistrations, Teams, TeamPlayers, MatchResults, Goals, RatingHistory, PlayerStatistics

3. Cardinality Rules

Users (1) -> (N) Groups [Owner] Users (N) <-> (N) Groups عبر GroupMembers Groups (1) -> (N) Fields Groups (1) -> (N) Matches Matches (1) -> (N) MatchRegistrations Matches (1) -> (2) Teams Teams (1) -> (N) TeamPlayers Matches (1) -> (1) MatchResults Matches (1) -> (N) Goals Users (1) -> (N) RatingHistory Users (1) -> (1) PlayerStatistics

4. Business Rules

- أي مستخدم يمكنه إنشاء مجموعة. - المجموعة قد تكون عامة أو خاصة. - اللاعب يمكنه الانضمام لأكثر من مجموعة. - يمنع التسجيل في مباريات متداخلة زمنياً. - أول المسجلين يحصلون على المقاعد الأساسية. - البقية يدخلون الاحتياط حسب أولوية التسجيل. - عند الاعتذار يتم تصعيد أول لاعب احتياط. - يعاد توزيع الفرق تلقائياً بعد أي تغيير مؤثر. - مجموع الأهداف المسجلة يجب أن يساوي نتيجة المباراة. - التقييم يتغير بناءً على الفوز والخسارة والأهداف وأفضل لاعب.

5. Data Dictionary Summary

Users: بيانات اللاعبين. Groups: مجتمعات اللاعبين. GroupMembers: عضوية المجموعات. Fields: الملاعب. Matches: المباريات. MatchRegistrations: التسجيلات والاحتياط. Teams: الفرق الناتجة. TeamPlayers: أعضاء الفرق. MatchResults: نتائج المباريات. Goals: الأهداف. RatingHistory: سجل التقييمات. PlayerStatistics: الإحصائيات المجمعة.

6. Constraints

Overall Rating بين 1 و 10. Primary Position مطلوب. Match End > Match Start. لا يمكن تكرار العضوية لنفس اللاعب في نفس المجموعة. لا يمكن تكرار التسجيل لنفس اللاعب في نفس المباراة.

7. Future Scalability Notes

يدعم تعدد المجموعات. يدعم التوسع التجاري مستقبلاً. يدعم إضافة اشتراكات ومدفوعات لاحقاً دون إعادة هيكلة جوهرية.