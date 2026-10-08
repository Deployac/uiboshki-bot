"""
Тариф человека (PLAN.md «ИИ и подписка»): от него зависит только ИИ.

  own  — своя группа (УИБО-03-24) и старосты: ИИ как раньше (AI_DAILY_LIMIT);
  sub  — подписка (subscriptions.until не прошла): до AI_SUB_DAILY в день;
  base — все остальные: проба ИИ (ai_quota) и конспекты с недельным лимитом.

Всё остальное — расписание, дедлайны, баллы СДО, файлы, поиск по лекциям —
бесплатно всем и от тарифа не зависит.
"""

OWN, SUB, BASE = "own", "sub", "base"
NAMES = {OWN: "своя группа", SUB: "подписка", BASE: "база"}


async def plan_of(user_id: int) -> str:
    import config
    import groups
    from database import get_subscription, get_user_group
    from utils import today_msk
    if config.is_starosta(user_id):
        return OWN
    until = await get_subscription(user_id)
    if until and until >= today_msk().isoformat():
        return SUB
    if not groups.home_id():
        return OWN          # копия бота на одну группу (ICAL_URL без id) — тарифов нет
    gid = await get_user_group(user_id)
    if gid and gid == groups.home_id():
        return OWN
    if gid:
        from database import get_group
        g = await get_group(gid)
        if g and g["own"]:
            return OWN
    return BASE
