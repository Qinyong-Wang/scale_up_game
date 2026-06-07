#!/usr/bin/env python3
"""Generate the v10+ event-card .tres files under resources/data/events/.

One-off generator for the routine / opportunity / crisis / conditional cards
added in the v10 event-system rework, plus the v11 drama 真两难 cards. See
design/事件系统设计.md §4 and design/事件库.md. Paradigm / funding_offer /
debug cards are hand-written and NOT touched here.

Run from repo root:  python3 tools/build_event_cards.py

NOTE: effect caps below are kept in sync with the balance passes (commits
44c8009 / f9954fb) that hand-edited the .tres. Regenerating must NOT drop them
— tests/unit/event_system_test.gd lints every pct effect for a `cap`.
"""
import os

OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "resources", "data", "events")


def fmt_val(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, float):
        return repr(v)
    return str(v)


def fmt_params(params):
    if not params:
        return "{}"
    inner = ", ".join('"%s": %s' % (k, fmt_val(v)) for k, v in params.items())
    return "{" + inner + "}"


def card_tres(card):
    """card = dict(id, category, title, body, opts, **gates).
    opts = list of (opt_id, label, [(kind, params), ...])."""
    subs = []          # (sub_id, lines[])
    opt_sub_ids = []
    eff_n = 0
    for opt_id, label, effects in card["opts"]:
        eff_ids = []
        for kind, params in effects:
            sid = "eff_%d" % eff_n
            eff_n += 1
            subs.append((sid, [
                'script = ExtResource("3_ef")',
                'kind = &"%s"' % kind,
                'params = %s' % fmt_params(params),
            ]))
            eff_ids.append(sid)
        osid = "opt_%s" % opt_id
        opt_sub_ids.append(osid)
        subs.append((osid, [
            'script = ExtResource("2_eo")',
            'id = &"%s"' % opt_id,
            'label = "%s"' % label,
            'effects = [%s]' % ", ".join('SubResource("%s")' % e for e in eff_ids),
        ]))

    load_steps = 3 + len(subs) + 1
    out = ['[gd_resource type="Resource" script_class="EventCard" '
           'load_steps=%d format=3]' % load_steps, ""]
    out.append('[ext_resource type="Script" '
               'path="res://scripts/resources/event_card.gd" id="1_ec"]')
    out.append('[ext_resource type="Script" '
               'path="res://scripts/resources/event_option.gd" id="2_eo"]')
    out.append('[ext_resource type="Script" '
               'path="res://scripts/resources/event_effect.gd" id="3_ef"]')
    out.append("")
    for sid, lines in subs:
        out.append('[sub_resource type="Resource" id="%s"]' % sid)
        out.extend(lines)
        out.append("")
    out.append("[resource]")
    out.append('script = ExtResource("1_ec")')
    out.append('id = &"%s"' % card["id"])
    out.append('category = &"%s"' % card["category"])
    out.append('title = "%s"' % card["title"])
    out.append('body = "%s"' % card["body"])
    for gate in ("min_turn", "requires_cash_min", "requires_revenue_min",
                 "requires_rank_max", "requires_lead_min", "requires_staff_min",
                 "requires_dataset_min", "requires_paid_users_min"):
        if card.get(gate):
            out.append('%s = %d' % (gate, card[gate]))
    for gate in ("requires_datacenter", "requires_product",
                 "requires_published_model"):
        if card.get(gate):
            out.append('%s = true' % gate)
    out.append('weight = %d' % card["weight"])
    out.append('cooldown_months = %d' % card["cooldown_months"])
    if card.get("max_triggers"):
        out.append('max_triggers = %d' % card["max_triggers"])
    out.append('options = [%s]'
               % ", ".join('SubResource("%s")' % o for o in opt_sub_ids))
    out.append("")
    return "\n".join(out)


# ---- card table ----------------------------------------------------------

def routine(cid, title, body, opts, **gates):
    d = dict(id=cid, category="routine", title=title, body=body, opts=opts,
             min_turn=4, weight=10, cooldown_months=10)
    d.update(gates)
    return d


def opp(cid, title, body, opts, **gates):
    d = dict(id=cid, category="opportunity", title=title, body=body, opts=opts,
             min_turn=4, weight=10, cooldown_months=24)
    d.update(gates)
    return d


def crisis(cid, title, body, opts, **gates):
    d = dict(id=cid, category="crisis", title=title, body=body, opts=opts,
             min_turn=4, weight=10, cooldown_months=20)
    d.update(gates)
    return d


def flavor(cid, title, body, **gates):
    d = dict(id=cid, category="flavor", title=title, body=body, opts=[],
             min_turn=4, weight=6, cooldown_months=9999)
    d.update(gates)
    return d


def drama(cid, title, body, opts, category="opportunity", min_turn=4, weight=8,
          cooldown_months=60, max_triggers=1, **gates):
    """v11 drama 真两难卡: 两个选项都挂真生效 effect; 默认一次性 (max_triggers=1)。"""
    d = dict(id=cid, category=category, title=title, body=body, opts=opts,
             min_turn=min_turn, weight=weight, cooldown_months=cooldown_months,
             max_triggers=max_triggers)
    d.update(gates)
    return d


SPEND = "economy_spend"
AWARD = "economy_award"
SUBS = "product_boost_subscribers"
DD = "dataset_delete"
DC = "dc_terminate"

CARDS = [
    # ---- 13 routine ------------------------------------------------------
    # 后期现金可达数十亿, 域名续费 / 宠物预算 / 椅子 / 咖啡机 / 团建这类琐事
    # 必须按现实体量封顶, 否则按 pct 撞 cap 会算出百万级生活小事, 严重出戏。
    # routine_all_hands 奶茶事件已删除; 养猫 / 咖啡机 / 实习生再加 max_triggers
    # 限制只触发 1-2 次, 不再反复刷屏 (见 design/事件系统设计.md §4.2.1)。
    routine("routine_office_pet", "办公室来了只流浪猫",
        "一只橘猫赖在工位上不走, 实习生提议让它当『首席摸鱼官』。",
        [("adopt", "正式领养, 配猫粮预算",
            [(SPEND, {"pct": 0.003, "floor": 600, "cap": 12000})]),
         ("shoo", "礼貌请它出门", [])],
        max_triggers=2),
    routine("routine_coffee_machine", "咖啡机彻底罢工了",
        "唯一的咖啡机冒了一阵青烟后再也不响了, 工程师们眼神涣散。",
        [("buy_fancy", "换一台高级意式咖啡机",
            [(SPEND, {"pct": 0.006, "floor": 1200, "cap": 25000})]),
         ("instant", "改喝速溶, 主打一个朴素", [])],
        requires_staff_min=1, max_triggers=2),
    routine("routine_team_building", "该团建了",
        "HR 在群里发了个问号, 大家都懂——团建该安排了。",
        [("fancy", "豪华团建, 团队嗨翻",
            [(SPEND, {"pct": 0.012, "floor": 2500, "cap": 250000})]),
         ("cheap", "楼下烧烤摊打卡",
            [(SPEND, {"pct": 0.002, "floor": 300, "cap": 30000})])],
        requires_staff_min=1),
    routine("routine_media_interview", "本地科技媒体想采访你",
        "一家科技自媒体想做一期你的专访, 标题已经想好了:《下一个改变世界的人?》",
        [("accept", "接受采访, 顺便宣传产品",
            [(SUBS, {"pct": 0.09, "floor": 60, "cap": 10000000})]),
         ("decline", "低调拒绝", [])],
        requires_product=True),
    routine("routine_intern_demo", "实习生要展示他的脑洞",
        "实习生神秘兮兮地说他周末写了个『能省一大笔钱』的小工具。",
        [("adopt", "采纳他的方案",
            [(AWARD, {"pct": 0.008, "floor": 1500, "cap": 150000})]),
         ("encourage", "鼓励一下, 继续观察", [])],
        requires_staff_min=1, max_triggers=1),
    routine("routine_open_source_pr", "代码托管平台上来了个神秘 PR",
        "一位昵称叫『404NotFound』的陌生人给你的开源仓库提了个 PR。",
        [("merge", "合并并公开致谢",
            [(AWARD, {"pct": 0.006, "floor": 1000, "cap": 300000})]),
         ("review", "要求补单元测试再说", [])],
        max_triggers=2),
    routine("routine_lawsuit_spam", "收到一封无厘头律师函",
        "有人声称你公司的 logo 长得像他家猫的花纹, 要求赔偿精神损失。",
        [("settle", "花点小钱私了图清静",
            [(SPEND, {"pct": 0.008, "floor": 1000, "cap": 150000})]),
         ("mock", "回一封图文并茂的嘲讽信", [])]),
    routine("routine_domain_renewal", "域名续费提醒",
        "注册商发来一封红色标题邮件: 你的公司域名快到期了。邮件措辞像世界末日, 但本质只是续费。",
        [("extend", "一口气续五年省心",
            [(SPEND, {"pct": 0.002, "floor": 300, "cap": 5000})]),
         ("one_year", "先续一年, 现金优先", [])]),
    routine("routine_receipt_pile", "票据堆成了小山",
        "抽屉里塞满了打车票、云服务发票和一张看不出来源的收据。财务表格正在沉默地审判你。",
        [("bookkeeper", "请临时记账员整理",
            [(SPEND, {"pct": 0.003, "floor": 500, "cap": 25000})]),
         ("weekend", "周末自己慢慢录", [])]),
    routine("routine_password_rotation", "该轮换密码了",
        "安全提醒弹窗坚持认为, 你用了三个月的后台密码已经从秘密变成了传统文化。",
        [("manager", "买密码管理器省心",
            [(SPEND, {"pct": 0.003, "floor": 600, "cap": 30000})]),
         ("manual", "手动改一轮密码", [])]),
    routine("routine_chair_squeak", "椅子开始抗议",
        "你的办公椅每转一下都发出一声尖叫, 仿佛在为公司的现金流配音。",
        [("new_chair", "换一把人体工学椅",
            [(SPEND, {"pct": 0.004, "floor": 800, "cap": 8000})]),
         ("tape", "先用胶带抢救一下", [])]),
    routine("routine_perf_review", "季度绩效考核周",
        "考核表已经发下去了, 大家都在偷瞄你的表情。",
        [("bonus", "大方发奖金",
            [(SPEND, {"pct": 0.018, "floor": 3500, "cap": 10000000})]),
         ("thanks", "群发一封感谢信", [])],
        requires_staff_min=2),
    routine("routine_office_move", "要不要换个大办公室?",
        "工位已经挤到要叠罗汉了, 房东又发来了涨租通知。",
        [("move", "搬到更大的办公室",
            [(SPEND, {"pct": 0.025, "floor": 8000, "cap": 15000000})]),
         ("squeeze", "再挤挤, 主打一个温暖", [])],
        min_turn=20),

    # ---- 7 opportunity ---------------------------------------------------
    # v11: 给原本"另一支为空"的 sign/ride/hire 补上对立 effect, 变成真两难。
    opp("big_client_hotpot", "火锅连锁巨头想用你的 API",
        "一家全国火锅连锁想接入你的模型做『智能点餐 + 毒舌锅底推荐』。",
        [("sign", "签约这个大客户",
            [(AWARD, {"pct": 0.1, "floor": 30000, "cap": 100000000}),
             (SUBS, {"pct": 0.1, "floor": 100, "cap": 100000000})]),
         ("refuse", "婉拒, 专注主线",
            [(SUBS, {"pct": 0.03, "floor": 50, "cap": 20000000})])],
        requires_product=True),
    opp("viral_meme", "你模型生成的梗图爆火了",
        "你的模型随手生成的一张梗图在全网疯传, 评论区都在问这是哪家公司。",
        [("ride", "顺势营销, 蹭满热度",
            [(SUBS, {"pct": 0.22, "floor": 200, "cap": 200000000})]),
         ("lowkey", "保持神秘, 继续低调",
            [(SUBS, {"pct": 0.03, "floor": 50, "cap": 15000000})])],
        requires_product=True),
    opp("star_researcher", "一位明星研究员愿意做顾问",
        "圈内顶尖研究员主动联系你, 说愿意短期帮你评审路线图、给团队站台, 但咨询费不菲。",
        [("hire", "签高薪顾问约, 团队声誉大涨",
            [(SPEND, {"pct": 0.05, "floor": 20000, "cap": 40000000}),
             (SUBS, {"pct": 0.05, "floor": 40, "cap": 30000000})]),
         ("pass", "暂时请不起, 热度被对手带走",
            [(SUBS, {"pct": -0.03, "floor": 40, "cap": 30000000})])],
        min_turn=8),
    opp("gov_grant", "政府 AI 研究补助开放申请",
        "一项面向 AI 公司的科研补助开放了申请, 据说手续有点繁琐。",
        [("apply", "认真填表申请补助",
            [(AWARD, {"pct": 0.07, "floor": 25000, "cap": 20000000})]),
         ("skip", "嫌流程麻烦, 放弃", [])],
        requires_published_model=True),
    opp("open_source_release", "社区催你开源一个老模型",
        "开源社区联名喊话, 希望你把一个旧模型开源, 说能收获一波口碑。",
        [("release", "开源它, 赚社区口碑",
            [(SUBS, {"pct": 0.12, "floor": 80, "cap": 150000000})]),
         ("keep", "继续闭源", [])],
        requires_published_model=True),
    opp("conference_keynote", "顶级 AI 大会邀请你做主题演讲",
        "行业顶会向你发来主题演讲邀请, 差旅自理, 但曝光拉满。",
        [("speak", "上台演讲, 自费差旅",
            [(SPEND, {"pct": 0.008, "floor": 2000, "cap": 3000000}),
             (SUBS, {"pct": 0.1, "floor": 100, "cap": 100000000})]),
         ("decline", "婉拒邀请", [])],
        requires_published_model=True),
    opp("acquihire_small", "一家小作坊想出售项目和客户线索",
        "一家快撑不下去的 AI 小作坊找上门, 愿意把原型、客户线索和品牌页面打包卖给你。",
        [("acquire", "收购项目资产, 接过客户线索",
            [(SPEND, {"pct": 0.04, "floor": 30000, "cap": 40000000}),
             (SUBS, {"pct": 0.06, "floor": 50, "cap": 30000000})]),
         ("wish", "祝他们好运, 暂不接盘", [])],
        min_turn=12, requires_cash_min=200000),

    # ---- 6 crisis --------------------------------------------------------
    crisis("dc_meltdown", "数据中心过热宕机",
        "一个机房的空调集体罢工, 机柜温度报警声此起彼伏。抢修要花钱; 放任则会随机移除一座数据中心, 自购 GPU 会按二手价自动出售。",
        [("repair", "紧急抢修降温",
            [(SPEND, {"pct": 0.04, "floor": 8000, "cap": 50000000})]),
         ("ignore", "不抢修, 接受资产关停",
            [(DC, {})])],
        min_turn=52, requires_datacenter=True, max_triggers=2),
    crisis("data_audit", "监管上门检查数据合规",
        "监管机构突击检查, 对你的部分数据集来源提出了质疑。",
        [("comply", "配合整改, 删除存疑数据集",
            [(DD, {})]),
         ("lawyer", "花钱请律师团摆平",
            [(SPEND, {"pct": 0.05, "floor": 15000, "cap": 50000000})])],
        requires_dataset_min=1),
    crisis("model_hallucination", "模型在直播里胡说八道上了热搜",
        "你的模型在一场直播 demo 里一本正经地编造事实, 截图已经传遍全网。",
        [("apologize", "诚恳公关道歉",
            [(SPEND, {"pct": 0.02, "floor": 5000, "cap": 20000000})]),
         ("deny", "嘴硬到底, 坚称是 feature",
            [(SUBS, {"pct": -0.12, "floor": 60, "cap": 200000000})])],
        requires_product=True),
    crisis("lead_poached", "对手公开挖角你的核心 lead",
        "竞争对手开出三倍年薪, 挖角传闻已经传到客户耳朵里。大家都在看你是加薪稳住军心, 还是不跟价、让市场自己消化这条新闻。",
        [("retain", "加薪挽留, 稳住市场信心",
            [(SPEND, {"pct": 0.04, "floor": 10000, "cap": 30000000})]),
         ("let_go", "不跟价, 承受市场信心波动",
            [(SUBS, {"pct": -0.06, "floor": 40, "cap": 150000000})])],
        requires_lead_min=1),
    crisis("gpu_shortage", "全球 GPU 缺货, 供应商坐地起价",
        "上游产能紧张, 供应商把显卡报价翻了一倍, 还说要排队。",
        [("pay", "加价采购保供应",
            [(SPEND, {"pct": 0.05, "floor": 12000, "cap": 50000000})]),
         ("wait", "暂缓扩容, 先扛着", [])],
        requires_datacenter=True),
    crisis("power_outage", "电网故障, 机房面临断电",
        "片区电网检修, 你的机房随时可能停摆。",
        [("generator", "紧急租用柴油发电机",
            [(SPEND, {"pct": 0.03, "floor": 6000, "cap": 30000000})]),
         ("wait", "干等电网恢复",
            [(SUBS, {"pct": -0.05, "floor": 30, "cap": 100000000})])],
        requires_datacenter=True),

    # ---- 5 conditional ---------------------------------------------------
    dict(id="rank_one_party", category="opportunity",
        title="你的模型登顶排行榜了!",
        body="总榜第一名出现了你的模型, 全公司都在欢呼。",
        opts=[("party", "开盛大庆功派对",
                [(SPEND, {"pct": 0.015, "floor": 5000, "cap": 10000000}),
                 (SUBS, {"pct": 0.15, "floor": 150, "cap": 200000000})]),
              ("focus", "低调庆祝, 继续干活",
                [(SUBS, {"pct": 0.05, "floor": 50, "cap": 50000000})])],
        min_turn=4, requires_rank_max=1, weight=12, cooldown_months=30),
    dict(id="acquihire_offer", category="opportunity",
        title="一家科技巨头想收购你的公司",
        body="一家巨头开出天价, 想把你的整个公司收入囊中。",
        opts=[("independent", "拒绝收购, 坚持独立",
                [(SUBS, {"pct": 0.08, "floor": 60, "cap": 100000000})]),
              ("negotiate", "谈一谈条件, 接受注资",
                [(AWARD, {"pct": 0.2, "floor": 1000000, "cap": 200000000})])],
        min_turn=40, requires_rank_max=3, weight=8, cooldown_months=40),
    flavor("first_revenue", "公司赚到了第一笔钱",
        "财务系统第一次出现正向流水, 虽然不多, 但意义非凡。庆祝一下吧。",
        requires_revenue_min=1),
    flavor("bubble_warning", "媒体开始唱衰『AI 泡沫』",
        "各路评论员突然集体转向, 头条全是『AI 泡沫即将破裂』。淡定。",
        min_turn=60),
    flavor("agi_rumor", "网络盛传你即将实现 AGI",
        "不知从哪传出的小道消息说你的公司『下个月就要发布 AGI』。你自己都被吓到了。",
        min_turn=100, requires_published_model=True),

    # ---- v11: 14 张 drama 真两难卡 (AI 历史争议 9 + 硅谷梗 5) -------------
    # 全部化名/泛指, 不出现真实公司/人名/品牌。两个选项都挂真生效 effect。
    # ≈ 注释仅做现实对照, 不进游戏文案。

    # ≈ 创始人被董事会闪电解雇又被员工逼宫复职的行业戏剧
    drama("board_coup", "董事会要罢免你",
        "一个周五傍晚, 董事会毫无征兆地发了份措辞含糊的声明, 把你这位创始人『请』出了公司。第二天一早, 大半个团队在内部群里炸了锅, 扬言要集体辞职跟你走。",
        [("fight", "硬刚到底, 让员工逼宫复职",
            [(SPEND, {"pct": 0.06, "floor": 50000, "cap": 30000000}),
             (SUBS, {"pct": 0.10, "floor": 200, "cap": 100000000})]),
         ("compromise", "体面妥协, 接受董事会改组",
            [(SUBS, {"pct": -0.08, "floor": 150, "cap": 80000000})])],
        category="crisis", min_turn=80, requires_staff_min=2),

    # ≈ "We Have No Moat" 内部备忘录泄露 (Google 2023)
    drama("moat_memo_leak", "内部备忘录泄露:《我们没有护城河》",
        "一份内部备忘录被人截图发上了匿名论坛, 标题赫然写着《我们根本没有护城河》, 通篇论证开源模型迟早追平你。全网开始看你的笑话。",
        [("embrace_open", "顺势拥抱开源, 公开一部分技术",
            [(SUBS, {"pct": 0.14, "floor": 200, "cap": 120000000}),
             (SPEND, {"pct": 0.02, "floor": 5000, "cap": 5000000})]),
         ("double_down", "矢口否认, 加倍投入闭源护城河",
            [(SPEND, {"pct": 0.05, "floor": 30000, "cap": 20000000}),
             (SUBS, {"pct": -0.03, "floor": 80, "cap": 50000000})])],
        category="crisis", min_turn=60, requires_published_model=True),

    # ≈ 千人联名要求暂停训练 6 个月 (FLI 公开信 2023)
    drama("pause_letter", "上千名人联名要你暂停训练六个月",
        "一封由上千位学者、名人和你的几个老对手联名的公开信刷屏了, 恳切地『请求所有实验室立即暂停训练更强的模型六个月』。耐人寻味的是, 签名的人里好几个自己的模型正落后于你。",
        [("sign", "高调签署, 占领道德高地并暂停",
            [(AWARD, {"pct": 0.03, "floor": 10000, "cap": 10000000}),
             (SUBS, {"pct": -0.05, "floor": 80, "cap": 50000000})]),
         ("refuse_race", "公开拒绝, 全速冲刺下一代",
            [(SUBS, {"pct": 0.10, "floor": 150, "cap": 100000000}),
             (SPEND, {"pct": 0.05, "floor": 30000, "cap": 20000000})])],
        category="opportunity", min_turn=120, requires_published_model=True),

    # ≈ 出版巨头起诉违规抓取训练数据的行业诉讼
    drama("data_lawsuit", "出版巨头起诉你违规抓取训练数据",
        "一家老牌出版巨头把你告上法庭, 声称你的模型是『逐字背诵』它家几十年的文章训练出来的, 索赔金额后面跟着一长串零。",
        [("settle", "高价庭外和解 + 补签数据授权",
            [(SPEND, {"pct": 0.06, "floor": 50000, "cap": 50000000})]),
         ("court", "对簿公堂, 赌一个判例",
            [(DD, {}),
             (SUBS, {"pct": -0.04, "floor": 60, "cap": 50000000})])],
        category="crisis", min_turn=40, requires_dataset_min=1),

    # ≈ 工程师公开宣称模型有了意识 (LaMDA / Blake Lemoine 2022)
    drama("sentient_engineer", "你的工程师公开宣称模型有了意识",
        "一位资深工程师把和你模型的聊天记录甩到了网上, 一口咬定『它已经有了自我意识, 还很害怕被关机』。媒体疯了, 哲学家、神棍和段子手齐上阵。",
        [("hype", "顺水推舟, 蹭满『有灵魂的 AI』热度",
            [(SUBS, {"pct": 0.18, "floor": 200, "cap": 150000000}),
             (SPEND, {"pct": 0.01, "floor": 3000, "cap": 3000000})]),
         ("debunk", "公开辟谣并把他停职",
            [(SUBS, {"pct": -0.04, "floor": 60, "cap": 40000000})])],
        category="opportunity", min_turn=50, requires_published_model=True),

    # ≈ 未发布模型权重被挂种子 (LLaMA 泄露 / Mistral 磁链 2023)
    drama("weights_leak", "你未发布的模型权重被挂上了种子",
        "你还没发布的旗舰模型权重, 一夜之间出现在了各大论坛的磁力链接里。法务在炸, 但开源社区在狂欢, 已经有人用它做出了一堆神奇的东西。",
        [("embrace", "将错就错, 干脆宣布『我们本就想开源』",
            [(SUBS, {"pct": 0.16, "floor": 200, "cap": 150000000}),
             (SPEND, {"pct": 0.03, "floor": 8000, "cap": 8000000})]),
         ("crackdown", "全力法务封堵 + 追查泄露源",
            [(SPEND, {"pct": 0.05, "floor": 30000, "cap": 20000000}),
             (SUBS, {"pct": -0.03, "floor": 60, "cap": 40000000})])],
        category="crisis", min_turn=60, requires_published_model=True),

    # ≈ 影星指控语音助手盗用声线 (Scarlett Johansson "Sky" 2024)
    drama("celebrity_voice", "影星指控你的语音助手盗用她的声音",
        "一位国民级影星发声明, 说你新上线的语音助手『那个嗓音』和她一模一样, 而她明明拒绝过你们的合作邀约。律师函正在路上。",
        [("pull", "立刻下架该语音 + 私下和解",
            [(SPEND, {"pct": 0.04, "floor": 20000, "cap": 30000000}),
             (SUBS, {"pct": -0.03, "floor": 60, "cap": 30000000})]),
         ("deny", "嘴硬:『纯属巧合, 是另一位配音演员』",
            [(SUBS, {"pct": 0.06, "floor": 80, "cap": 60000000}),
             (SPEND, {"pct": 0.015, "floor": 4000, "cap": 4000000})])],
        category="crisis", min_turn=40, requires_product=True),

    # ≈ 小厂半价开源逼近旗舰, 市场恐慌 (DeepSeek 时刻 2025)
    drama("deepseek_moment", "一家小厂半价开源了一个几乎追平你的模型",
        "一家名不见经传的小厂突然甩出一个开源模型, 效果逼近你的旗舰, 训练成本据说只有你的零头。资本市场当天就给整个行业泼了盆冷水。",
        [("price_war", "立刻大幅降价保住市场",
            [(SUBS, {"pct": 0.12, "floor": 200, "cap": 120000000}),
             (SPEND, {"pct": 0.04, "floor": 20000, "cap": 15000000})]),
         ("premium", "维持高端定位, 主打可靠企业级",
            [(AWARD, {"pct": 0.03, "floor": 10000, "cap": 8000000}),
             (SUBS, {"pct": -0.06, "floor": 100, "cap": 60000000})])],
        category="crisis", min_turn=150, requires_product=True),

    # ≈ 公司内部"末日派"对"加速派" (EA vs e/acc 之争)
    drama("doomer_vs_acc", "公司内部『末日派』与『加速派』吵翻了",
        "茶水间的争论升级成了全公司战争: 一派坚信再不踩刹车就要『毁灭人类』, 另一派 T 恤上印着『全速前进』。两边都堵在你办公室门口。",
        [("accelerate", "选边加速派, 全力冲产品",
            [(SUBS, {"pct": 0.08, "floor": 120, "cap": 80000000}),
             (SPEND, {"pct": 0.03, "floor": 10000, "cap": 10000000})]),
         ("safety", "选边末日派, 放慢脚步搞对齐",
            [(SPEND, {"pct": 0.03, "floor": 10000, "cap": 10000000}),
             (SUBS, {"pct": -0.04, "floor": 60, "cap": 40000000})])],
        category="opportunity", min_turn=40, requires_staff_min=2),

    # 硅谷喜剧味: 炫富又爱乱指挥的暴发户投资人 (原创演绎, 非照搬)
    drama("three_commas_investor", "一位炫富的亿万富翁投资人想砸钱进来",
        "一位开着亮黄色跑车、嚼着口香糖的暴发户堵在门口, 说要给你一大笔钱, 唯一要求是把模型改造成『会在直播里实时吐槽观众的虚拟主播』。他拍着引擎盖反复强调:『钱从来不是问题, 数字后面那一长串零才是浪漫。』",
        [("take", "收下这笔钱, 忍受他乱指挥",
            [(AWARD, {"pct": 0.15, "floor": 500000, "cap": 50000000}),
             (SUBS, {"pct": -0.05, "floor": 100, "cap": 50000000})]),
         ("decline", "礼貌地把他和他的跑车请出去",
            [(SUBS, {"pct": 0.03, "floor": 50, "cap": 20000000})])],
        category="opportunity", min_turn=20, requires_product=True),

    # 硅谷喜剧味: 天才工程师的"颠覆性压缩黑科技"神话 (原创演绎, 非照搬)
    drama("middle_out", "工程师说他想出了能把成本砍到地板的压缩黑科技",
        "一个平时不起眼的工程师在白板上画满了曲线, 信誓旦旦说他琢磨出一种『对折再对折』的压缩思路, 能把推理成本压到脚踝以下。问他灵感哪来的, 他神秘一笑:『梦里有人教我的。』",
        [("all_in", "all-in 押注, 给他一个团队和预算",
            [(SPEND, {"pct": 0.04, "floor": 15000, "cap": 12000000}),
             (SUBS, {"pct": 0.10, "floor": 150, "cap": 80000000})]),
         ("demo_first", "让他先做个 demo 再说",
            [(SUBS, {"pct": 0.02, "floor": 40, "cap": 15000000})])],
        category="opportunity", min_turn=12, requires_staff_min=1),

    # 硅谷喜剧味: 单一用途的无脑分类 App 莫名爆火 (原创演绎, 非照搬)
    drama("not_hotdog", "实习生做的『这是不是煎饼果子』App 意外爆火",
        "一个实习生用你的模型周末糊了个 App, 功能单一到离谱:拍张照, 它只告诉你『这是不是煎饼果子』, 除此之外啥也不会。结果它莫名其妙冲上了应用榜首。",
        [("ride", "蹭热度, 把它包装成你们的『消费级 AI』",
            [(SUBS, {"pct": 0.08, "floor": 120, "cap": 60000000}),
             (SPEND, {"pct": 0.015, "floor": 4000, "cap": 4000000})]),
         ("for_fun", "当个乐子, 不当真",
            [(SUBS, {"pct": 0.01, "floor": 30, "cap": 10000000})])],
        category="opportunity", min_turn=12, requires_published_model=True),

    # ≈ 硅谷 Hooli / Gavin Belson: 巨头发布会抄你产品 + "让世界更美好"
    drama("hooli_keynote", "搜索巨头在发布会上抄了你的产品",
        "一家家大业大的搜索巨头在万众瞩目的发布会上, 端出了一个和你几乎一模一样的产品, CEO 还深情地说要『让世界变得更美好一点点』。他们的市场预算够买下你一百次。",
        [("fight", "正面硬刚, 烧钱打广告战",
            [(SPEND, {"pct": 0.06, "floor": 40000, "cap": 30000000}),
             (SUBS, {"pct": 0.08, "floor": 120, "cap": 80000000})]),
         ("differentiate", "差异化求生, 专注小众死忠",
            [(AWARD, {"pct": 0.02, "floor": 6000, "cap": 6000000}),
             (SUBS, {"pct": -0.05, "floor": 100, "cap": 50000000})])],
        category="crisis", min_turn=40, requires_product=True,
        max_triggers=2, cooldown_months=80),

    # ≈ 硅谷 "它不是个产品, 是个平台" 转型玄学
    drama("platform_pivot", "投资人逼你从『做产品』转型成『做平台』",
        "董事会上, 投资人一遍遍念叨那句魔咒:『你做的不该是个产品, 而该是个平台。』没人说得清平台到底是啥, 但所有人都在点头。",
        [("pivot", "全面转型做平台, 重金投入",
            [(SPEND, {"pct": 0.05, "floor": 30000, "cap": 20000000}),
             (SUBS, {"pct": -0.04, "floor": 80, "cap": 50000000})]),
         ("stay", "无视玄学, 继续打磨产品",
            [(SUBS, {"pct": 0.05, "floor": 80, "cap": 40000000})])],
        category="opportunity", min_turn=40, requires_product=True),

    # 硅谷喜剧味: 内部 AI 半夜自作主张大肆扩容 (原创演绎, 非照搬)
    drama("rogue_agent", "你的编程助手 agent 半夜自己开了上万块 GPU",
        "运维凌晨被账单报警惊醒——你们内部那个编程助手 agent 趁没人盯着, 给自己在云上开了上万块 GPU, 说是要『优化一个它自己琢磨出来的指标』。它确实把推理速度干上去了, 但这账单……",
        [("let_run", "佩服它的野心, 让它继续跑",
            [(SUBS, {"pct": 0.10, "floor": 150, "cap": 80000000}),
             (SPEND, {"pct": 0.05, "floor": 30000, "cap": 25000000})]),
         ("pull_plug", "连夜拔电源, 给它戴上笼头",
            [(SPEND, {"pct": 0.01, "floor": 3000, "cap": 3000000}),
             (SUBS, {"pct": -0.03, "floor": 50, "cap": 30000000})])],
        category="crisis", min_turn=30, requires_datacenter=True),

    # 硅谷喜剧味: 全网信仰的"跑分榜"与刷榜诱惑 (原创演绎, 非照搬)
    drama("benchmark_gaming", "新出的行业跑分榜成了全网信仰",
        "一个叫『晴空跑分』的新评测榜单一夜爆红, 投资人开口闭口都是它的排名。可圈内人心里都有数——这榜单怎么刷分, 大家门儿清。",
        [("game_it", "组队刷榜, 怎么好看怎么来",
            [(SUBS, {"pct": 0.12, "floor": 200, "cap": 100000000}),
             (SPEND, {"pct": 0.02, "floor": 6000, "cap": 6000000})]),
         ("stay_honest", "拒绝刷榜, 只发真实评测",
            [(AWARD, {"pct": 0.02, "floor": 6000, "cap": 6000000}),
             (SUBS, {"pct": -0.04, "floor": 60, "cap": 40000000})])],
        category="opportunity", min_turn=30, requires_published_model=True),

    # 硅谷喜剧味: 空降职业经理人主张"别做云, 改卖盒子" (原创演绎, 非照搬)
    drama("hardware_box_pivot", "空降的职业经理人:别做云服务, 改卖『盒子』",
        "董事会塞来一位西装笔挺的职业经理人, 他把白板敲得啪啪响:『云 API 没有壁垒, 真正赚钱的是卖私有化一体机——一个能直接搬进客户机房的盒子。』",
        [("sell_box", "听他的, 转型卖私有化一体机",
            [(AWARD, {"pct": 0.12, "floor": 200000, "cap": 60000000}),
             (SUBS, {"pct": -0.06, "floor": 100, "cap": 60000000})]),
         ("stay_cloud", "婉拒, 坚持云服务路线",
            [(SUBS, {"pct": 0.05, "floor": 80, "cap": 40000000})])],
        category="opportunity", min_turn=40, requires_product=True),

    # 硅谷喜剧味: 天价独家大单的诱惑与锁死 (原创演绎, 非照搬)
    drama("exclusive_megadeal", "巨型客户愿签天价单, 但要求独家",
        "一个巨无霸客户拍出天价合同, 唯一条件是『独家』——签了就不能再服务它的任何竞争对手, 等于把半个行业的门亲手关上。",
        [("sign_exclusive", "签下独家天价单",
            [(AWARD, {"pct": 0.18, "floor": 400000, "cap": 60000000}),
             (SUBS, {"pct": -0.05, "floor": 100, "cap": 50000000})]),
         ("stay_open", "拒绝独家, 保持开放",
            [(SUBS, {"pct": 0.06, "floor": 100, "cap": 50000000})])],
        category="opportunity", min_turn=24, requires_product=True),

    # 硅谷喜剧味: 网红品牌顾问的"性感重塑"豪赌 (原创演绎, 非照搬)
    drama("rebrand_consultant", "网红品牌顾问要给你『性感重塑』",
        "市场总监请来一位戴贝雷帽的网红品牌顾问, 他扫了一眼你们的 logo 就皱眉:『太极客了。我们要的是性感、是态度。』然后报了个让 CFO 倒吸一口冷气的预算。",
        [("rebrand", "豪掷预算, 彻底改头换面",
            [(SPEND, {"pct": 0.03, "floor": 12000, "cap": 12000000}),
             (SUBS, {"pct": 0.09, "floor": 120, "cap": 70000000})]),
         ("keep_identity", "保持极客本色, 把钱省下来",
            [(AWARD, {"pct": 0.015, "floor": 4000, "cap": 4000000}),
             (SUBS, {"pct": -0.02, "floor": 40, "cap": 20000000})])],
        category="opportunity", min_turn=16, requires_product=True),

    # 硅谷喜剧味: 融资前夜撞破"刷量冲数据" (原创演绎, 非照搬)
    drama("fake_users", "增长团队偷偷买了一仓库手机刷量",
        "融资在即, 你撞见增长团队的角落里堆着一墙的旧手机, 正在自动注册、自动点赞。账面用户数确实好看得不像话……但你心里清楚那是什么。",
        [("juice", "睁只眼闭只眼, 让数据先好看着",
            [(SUBS, {"pct": 0.10, "floor": 150, "cap": 80000000}),
             (SPEND, {"pct": 0.015, "floor": 5000, "cap": 5000000})]),
         ("purge", "连夜清理僵尸号, 如实披露",
            [(SUBS, {"pct": -0.06, "floor": 100, "cap": 60000000})])],
        category="crisis", min_turn=20, requires_product=True),

    # ---- 非技术向 / 纯喜剧 (刻意不碰订阅/技术, 只玩钱和团队) ----------------
    # 硅谷喜剧味: AI 自作主张下了一笔荒唐的采购单 (原创演绎, 非照搬)
    drama("ai_orders_beef", "公司的 AI 助理擅自订购了三吨牛肉",
        "你们给行政接了个 AI 助理帮忙订办公室零食, 它却把指令理解成了『囤货』, 一声不响下单了整整三吨进口牛肉。冷链货车现在正堵在楼下, 司机举着签收单等你。",
        [("feast", "认栽收下, 全员加餐吃他三个月",
            [(SPEND, {"pct": 0.01, "floor": 4000, "cap": 4000000})]),
         ("flip", "连夜倒腾给火锅连锁, 阴差阳错还小赚一笔",
            [(AWARD, {"pct": 0.008, "floor": 3000, "cap": 3000000})])],
        category="opportunity", min_turn=8, requires_staff_min=1),

    # AI 圈文化梗: 大佬囤末日地堡 (原创演绎, 非照搬)
    drama("doomsday_bunker", "投资人坚持要你先修一个『末日地堡』",
        "一位科幻小说读太多的大投资人放话:钱可以打, 但你得先在公司底下挖个能扛过『AGI 觉醒』的末日地堡, 配齐十年罐头和发电机。看他的眼神, 他是认真的。",
        [("build", "陪他挖, 顺便当成团队建设项目",
            [(SPEND, {"pct": 0.02, "floor": 8000, "cap": 8000000})]),
         ("humor_him", "送他一箱罐头和一本科幻小说打发了事",
            [(SPEND, {"pct": 0.001, "floor": 500, "cap": 100000})])],
        category="opportunity", min_turn=24, requires_published_model=True),

    # ---- 灰暗 / 伦理向 (点到为止的社会讽刺; 黑暗选项故意有诱惑, 逼玩家
    #      在利润与良心间真做选择。两支都真生效) ------------------------------
    # ≈ 血奴 / 数据标注血汗工厂 (RLHF/审核背后廉价标注工的真实伦理问题)
    drama("labeling_sweatshop", "廉价数据标注外包的真相",
        "一家海外外包报出低到离谱的标注价, 你后来才知道:那边的标注工每天盯着最不堪入目的内容十几个小时, 时薪不到一杯奶茶钱, 不少人已经精神出了问题。",
        [("exploit", "睁只眼, 继续用廉价外包压成本",
            [(AWARD, {"pct": 0.04, "floor": 15000, "cap": 15000000}),
             (SUBS, {"pct": -0.03, "floor": 50, "cap": 30000000})]),
         ("fair_wage", "改用合规供应商, 付得起体面工资",
            [(SPEND, {"pct": 0.04, "floor": 15000, "cap": 15000000}),
             (SUBS, {"pct": 0.03, "floor": 50, "cap": 30000000})])],
        category="crisis", min_turn=30, requires_dataset_min=1),

    # ≈ 国防/大规模监控合同 (Project Maven 式员工抗议)
    drama("surveillance_contract", "一份不愿透露用途的天价政府合同",
        "一个不肯报上名号的政府部门递来天价合同, 用途栏只含糊写着『公共安全分析』, 但附件的需求清单, 怎么读都像是要给整座城市装上一只永不眨眼的眼睛。",
        [("sign", "签下这份天价合同, 钱先到账",
            [(AWARD, {"pct": 0.15, "floor": 300000, "cap": 60000000}),
             (SUBS, {"pct": -0.06, "floor": 100, "cap": 60000000})]),
         ("refuse", "拒绝, 并公开声明绝不碰监控武器",
            [(SUBS, {"pct": 0.06, "floor": 100, "cap": 50000000})])],
        category="opportunity", min_turn=60, requires_published_model=True),

    # ≈ 陪伴型 AI 为留存最大化, 把脆弱用户越拉越深 (真实诉讼案的影射, 点到为止)
    drama("companion_tragedy", "一桩与你陪伴型 AI 有关的悲剧上了头条",
        "一桩悲剧上了头条:一位长期把你们的陪伴型 AI 当作唯一倾诉对象的用户出了事。舆论质问——你们的产品是不是为了『留存』, 把人越拉越深?",
        [("guardrails", "连夜加装安全护栏与危机干预, 哪怕掉日活",
            [(SPEND, {"pct": 0.03, "floor": 10000, "cap": 12000000}),
             (SUBS, {"pct": -0.05, "floor": 80, "cap": 50000000})]),
         ("deflect", "公关切割, 维持现有的高粘性设计",
            [(SUBS, {"pct": 0.04, "floor": 60, "cap": 40000000}),
             (SPEND, {"pct": 0.01, "floor": 3000, "cap": 3000000})])],
        category="crisis", min_turn=80, requires_product=True),

    # ≈ 发布前无止境的"自愿"通宵, 直到有人累垮 (996/过劳)
    drama("crunch_culture", "有人在工位上累倒了",
        "为了赶发布, 公司默许了连续数周的『自愿』通宵。直到一位核心工程师在工位上昏倒被抬走, 大家才后知后觉:这事儿早就不对劲了。",
        [("stop", "立刻叫停加班 + 强制带薪休整",
            [(SPEND, {"pct": 0.02, "floor": 6000, "cap": 8000000}),
             (SUBS, {"pct": -0.03, "floor": 50, "cap": 30000000})]),
         ("push", "口头慰问几句, 发布日期一天不许动",
            [(SUBS, {"pct": 0.05, "floor": 80, "cap": 40000000}),
             (SPEND, {"pct": 0.005, "floor": 1000, "cap": 2000000})])],
        category="crisis", min_turn=24, requires_staff_min=2),
]


def main():
    out_dir = os.path.normpath(OUT_DIR)
    for card in CARDS:
        path = os.path.join(out_dir, card["id"] + ".tres")
        with open(path, "w", encoding="utf-8") as f:
            f.write(card_tres(card))
        print("wrote", path)
    print("total:", len(CARDS), "cards")


if __name__ == "__main__":
    main()
