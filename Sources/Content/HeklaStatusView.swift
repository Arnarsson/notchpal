import SwiftUI

// Per-agent detail content views — each shows the actual content for that agent type.

struct AgentDetailView: View {
    @Bindable var agent: AgentStatus
    var onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 36)

            // Back + status
            HStack(spacing: 8) {
                Button(action: onBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left").font(.system(size: 8, weight: .semibold))
                        Text("AGENTS").font(.system(size: 8, weight: .medium, design: .monospaced)).kerning(1)
                    }
                    .foregroundStyle(Hekla.dim)
                }
                .buttonStyle(.plain)

                Spacer()

                Circle().fill(agent.state.color).frame(width: 6, height: 6)
                    .shadow(color: agent.state.color.opacity(0.5), radius: 3)
                Text(agent.state.statusLabel)
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(agent.state.color)
                    .kerning(0.8)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 6)

            // Agent-specific content
            ScrollView(.vertical, showsIndicators: false) {
                switch agent.id {
                case "email": EmailsDetailContent()
                case "telegram": TelegramDetailContent()
                case "briefing": BriefingDetailContent()
                case "meeting": MeetingDetailContent()
                case "chat": ChatDetailContent()
                case "memory": MemoryDetailContent()
                case "log": LogDetailContent()
                default: GenericDetailContent(agent: agent)
                }
            }
            .padding(.horizontal, 14)
        }
    }
}

// MARK: - Emails

struct EmailsDetailContent: View {
    private let emails: [(initial: String, from: String, subject: String, preview: String, time: String, tag: String, handled: String?)] = [
        ("L", "Lina Moss", "Re: Q2 roadmap review", "Can HEKLA handle the schema rewrite end-to-end?", "11:48", "priority", nil),
        ("M", "M. Rao (Acme)", "§4.7 — one more ask", "We'd like cap on indirect damages at 1× ACV.", "10:22", "priority", nil),
        ("G", "GitHub", "[hekla/core] PR #412 merged", "indexer: batch embedding pass · merged by Jonah", "11:31", "low", "archived"),
        ("P", "Peder K.", "Thursday?", "still on for the lamb thing? bring the natural wine", "09:14", "personal", "drafted"),
        ("S", "Stripe", "Weekly payout · €4,208", "Payout initiated. 2 business days.", "09:12", "low", "archived"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Counts
            HStack(spacing: 12) {
                countBadge("12", "priority", Hekla.orange)
                countBadge("2", "drafted", Hekla.yellow)
                countBadge("34", "archived", Hekla.dim)
                Spacer()
            }
            .padding(.bottom, 8)

            ForEach(Array(emails.enumerated()), id: \.offset) { _, email in
                emailRow(email)
            }
        }
    }

    private func countBadge(_ count: String, _ label: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Text(count).font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundStyle(color)
            Text(label).font(.system(size: 8, design: .monospaced)).foregroundStyle(Hekla.dim)
        }
    }

    private func emailRow(_ e: (initial: String, from: String, subject: String, preview: String, time: String, tag: String, handled: String?)) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(e.initial)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(e.tag == "priority" ? Hekla.cream : Hekla.dim)
                .frame(width: 20, height: 20)
                .background(e.tag == "priority" ? Hekla.orange.opacity(0.2) : Hekla.cardHi, in: RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(e.from).font(.system(size: 10, weight: .semibold)).foregroundStyle(Hekla.cream).lineLimit(1)
                    Spacer()
                    Text(e.time).font(.system(size: 8, design: .monospaced)).foregroundStyle(Hekla.dim)
                }
                Text(e.subject).font(.system(size: 9, weight: .medium)).foregroundStyle(Hekla.body).lineLimit(1)
                Text(e.preview).font(.system(size: 9)).foregroundStyle(Hekla.dim).lineLimit(1)

                if let h = e.handled {
                    Text(h.uppercased())
                        .font(.system(size: 7, weight: .semibold, design: .monospaced))
                        .foregroundStyle(h == "drafted" ? Hekla.yellow : Hekla.dim)
                        .kerning(0.8)
                        .padding(.top, 1)
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Hekla.card))
        .padding(.bottom, 4)
    }
}

// MARK: - Telegram

struct TelegramDetailContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Peder chat — needs approval
            chatSection("Peder K.", handle: "@peder_k", needsApproval: true) {
                msgBubble("them", "still on for the lamb thing Thursday?", "12:58")
                draftBubble("yeah — 19:30 your place? bringing the natural wine I mentioned last week", confidence: 0.71)
            }

            // Nora chat
            chatSection("Nora K.", handle: "@noraaa", needsApproval: false) {
                msgBubble("them", "did you see the thing about the berlin residency?", "11:02")
                msgBubble("me", "yeah looking at it now", "11:14")
            }

            // Approval buttons — wired to real actions
            HStack(spacing: 6) {
                Button { AgentRegistry.shared.approveAgent(id: "telegram", action: "reject") } label: {
                    approvalBtn("Reject", Hekla.dim)
                }
                .buttonStyle(.plain)
                Button { AgentRegistry.shared.approveAgent(id: "telegram", action: "edit") } label: {
                    approvalBtn("Edit", Hekla.cardHi)
                }
                .buttonStyle(.plain)
                Button { AgentRegistry.shared.approveAgent(id: "telegram", action: "send") } label: {
                    approvalBtn("Send", Hekla.orange)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 4)
        }
    }

    private func chatSection(_ name: String, handle: String, needsApproval: Bool, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(name).font(.system(size: 10, weight: .semibold)).foregroundStyle(Hekla.cream)
                Text(handle).font(.system(size: 8, design: .monospaced)).foregroundStyle(Hekla.dim)
                Spacer()
                if needsApproval {
                    Text("DRAFT").font(.system(size: 7, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Hekla.yellow).kerning(0.8)
                }
            }
            content()
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Hekla.card))
    }

    private func msgBubble(_ who: String, _ text: String, _ time: String) -> some View {
        HStack {
            if who == "me" { Spacer(minLength: 40) }
            VStack(alignment: who == "me" ? .trailing : .leading, spacing: 2) {
                Text(text).font(.system(size: 10)).foregroundStyle(Hekla.body)
                Text(time).font(.system(size: 7, design: .monospaced)).foregroundStyle(Hekla.dim)
            }
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 6).fill(who == "me" ? Hekla.cardHi : Hekla.bg))
            if who != "me" { Spacer(minLength: 40) }
        }
    }

    private func draftBubble(_ text: String, confidence: Double) -> some View {
        HStack {
            Spacer(minLength: 40)
            VStack(alignment: .trailing, spacing: 2) {
                Text(text).font(.system(size: 10)).foregroundStyle(Hekla.body)
                Text("confidence \(String(format: "%.0f%%", confidence * 100))")
                    .font(.system(size: 7, design: .monospaced)).foregroundStyle(Hekla.yellow)
            }
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 6).stroke(Hekla.yellow.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4, 3])).background(Hekla.bg.clipShape(RoundedRectangle(cornerRadius: 6))))
        }
    }

    private func approvalBtn(_ title: String, _ bg: Color) -> some View {
        Text(title.uppercased())
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(bg == Hekla.orange ? .white : Hekla.cream)
            .kerning(1)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(bg, in: RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: - Briefing

struct BriefingDetailContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Morning, Sven.")
                .font(.system(size: 13, weight: .regular, design: .serif))
                .foregroundStyle(Hekla.cream)
            Text("Sunday, April 19")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(Hekla.dim)

            section("What matters today", [
                "Three meetings. 14:30 Acme renewal is the one.",
                "Twelve priority threads. Peder waiting on Thursday answer.",
                "Berlin flight Thursday 18:40. Hotel still unbooked.",
            ])
            section("Handled overnight", [
                "Thirty-four newsletters archived.",
                "Two low-stakes replies drafted. Awaiting approval.",
            ])
            section("Waiting on you", [
                "Acme MSA §4 redline sign-off. Elsa sent Friday 11:42.",
                "Confirm Peder Thursday 19:30.",
            ])

            Text("Sent to @sven on Telegram at 06:45")
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(Hekla.dim)
                .padding(.top, 4)
        }
    }

    private func section(_ title: String, _ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundStyle(Hekla.orange)
                .kerning(1.5)
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 6) {
                    Text("▸").font(.system(size: 9)).foregroundStyle(Hekla.dim)
                    Text(item).font(.system(size: 10)).foregroundStyle(Hekla.body)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(Hekla.card))
    }
}

// MARK: - Meeting Prep

struct MeetingDetailContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Acme MSA renewal").font(.system(size: 13, weight: .semibold)).foregroundStyle(Hekla.cream)
            HStack(spacing: 8) {
                Text("Today · 14:30 – 15:30").font(.system(size: 9, design: .monospaced)).foregroundStyle(Hekla.dim)
                Text("Google Meet").font(.system(size: 9, design: .monospaced)).foregroundStyle(Hekla.dim)
            }

            // Attendees
            HStack(spacing: 4) {
                ForEach(["Sven", "Elsa V.", "Peder K.", "M. Rao"], id: \.self) { name in
                    Text(name).font(.system(size: 8, weight: .medium)).foregroundStyle(Hekla.cream)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Hekla.cardHi, in: RoundedRectangle(cornerRadius: 3))
                }
            }

            section("Agenda draft", [
                "Recap §4 redline exchange. Friday → Monday.",
                "Acme asks: cap liability at 2× ACV. Template is 1.5×.",
                "Pricing: hold 12% uplift. 24mo vs 12mo term.",
                "Close: sign this week or slip to Q3.",
            ])

            VStack(alignment: .leading, spacing: 2) {
                Text("LAST TOUCH").font(.system(size: 8, weight: .medium, design: .monospaced)).foregroundStyle(Hekla.orange).kerning(1.5)
                Text("Fri 11:42 · Elsa to M. Rao — \"appreciated the redlines, one pushback on §4.7\"")
                    .font(.system(size: 9)).foregroundStyle(Hekla.body).italic()
            }
            .padding(8).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 6).fill(Hekla.card))
        }
    }

    private func section(_ title: String, _ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased()).font(.system(size: 8, weight: .medium, design: .monospaced)).foregroundStyle(Hekla.orange).kerning(1.5)
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 6) {
                    Text("▸").font(.system(size: 9)).foregroundStyle(Hekla.dim)
                    Text(item).font(.system(size: 10)).foregroundStyle(Hekla.body)
                }
            }
        }
        .padding(8).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(Hekla.card))
    }
}

// MARK: - Chat

struct ChatDetailContent: View {
    private let history: [(q: String, a: String, time: String, tools: [String])] = [
        ("what did I decide about the Berlin trip", "Thursday 18:40 out, back Sunday evening. Hotel still unbooked.", "11:30", ["memory.recall"]),
        ("rewrite this email colder", "Done. Cut 40% of the padding. Removed both apologies.", "10:44", []),
        ("what's the lithium thing MRao mentioned", "IEA critical-minerals report, March 2026. Pulled two quotes.", "09:12", ["web.search", "web.fetch"]),
    ]

    var body: some View {
        VStack(spacing: 8) {
            ForEach(Array(history.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: 6) {
                    // Question
                    HStack { Spacer(minLength: 40)
                        Text(item.q).font(.system(size: 10)).foregroundStyle(Hekla.cream)
                            .padding(6).background(RoundedRectangle(cornerRadius: 6).fill(Hekla.cardHi))
                    }
                    // Answer
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.a).font(.system(size: 10)).foregroundStyle(Hekla.body)
                            HStack(spacing: 4) {
                                Text(item.time).font(.system(size: 7, design: .monospaced)).foregroundStyle(Hekla.dim)
                                ForEach(item.tools, id: \.self) { tool in
                                    Text(tool).font(.system(size: 7, design: .monospaced)).foregroundStyle(Hekla.orange)
                                        .padding(.horizontal, 4).padding(.vertical, 1)
                                        .background(Hekla.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 2))
                                }
                            }
                        }
                        .padding(6).background(RoundedRectangle(cornerRadius: 6).fill(Hekla.card))
                        Spacer(minLength: 40)
                    }
                }
            }
        }
    }
}

// MARK: - Memory

struct MemoryDetailContent: View {
    private let results: [(ts: String, src: String, title: String, snippet: String, score: Double)] = [
        ("Fri 11:42", "email", "Elsa to M. Rao — redlines on §4", "…comfortable with §4 redline except §4.7 where we'd like a cap on indirect damages at 1× ACV…", 0.91),
        ("Wed 09:08", "briefing", "Morning briefing · Wed April 15", "…Acme renewal is the deal this week. They want §4 settled before signing…", 0.88),
        ("Apr 11", "chat", "How should I pitch the renewal", "…lean on the 12% uplift as inflation-indexed, not a price hike…", 0.84),
        ("Mar 22", "meeting", "Acme intro call prep", "…M. Rao is cautious, values process. Decision authority with M. Rao plus CFO…", 0.79),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Search
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 9)).foregroundStyle(Hekla.dim)
                Text("acme renewal").font(.system(size: 10)).foregroundStyle(Hekla.cream)
                Spacer()
                Text("4,812 ITEMS").font(.system(size: 7, weight: .medium, design: .monospaced)).foregroundStyle(Hekla.dim).kerning(0.8)
            }
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 6).fill(Hekla.card))

            ForEach(Array(results.enumerated()), id: \.offset) { _, r in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(r.src.uppercased()).font(.system(size: 7, weight: .medium, design: .monospaced)).foregroundStyle(Hekla.orange).kerning(0.8)
                        Text("·").foregroundStyle(Hekla.dim).font(.system(size: 8))
                        Text(r.ts).font(.system(size: 8, design: .monospaced)).foregroundStyle(Hekla.dim)
                        Spacer()
                        Text(String(format: "%.0f%%", r.score * 100)).font(.system(size: 8, weight: .medium, design: .monospaced)).foregroundStyle(Hekla.orange)
                    }
                    Text(r.title).font(.system(size: 10, weight: .medium)).foregroundStyle(Hekla.cream).lineLimit(1)
                    Text(r.snippet).font(.system(size: 9)).foregroundStyle(Hekla.dim).lineLimit(2)
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(Hekla.card))
            }
        }
    }
}

// MARK: - Log

struct LogDetailContent: View {
    private let today: [(t: String, agent: String, action: String, detail: String, pending: Bool)] = [
        ("13:42", "email", "Archived 3 newsletter threads", "Substack · The Browser · Stratechery", false),
        ("13:15", "memory", "Indexed 12 new items", "From Gmail poll · 38ms avg embed", false),
        ("12:58", "telegram", "Drafted reply to Peder K.", "Confidence 0.71 · held for approval", true),
        ("12:30", "email", "Polled Gmail", "7 new · 2 priority · 5 archived", false),
        ("11:48", "chat", "Answered Berlin trip question", "Memory recall · 5 hits · 320ms", false),
        ("06:45", "briefing", "Sent morning briefing", "3 meetings · 12 threads · via Telegram", false),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                countBadge("47", "today")
                countBadge("38", "yesterday")
                countBadge("214", "this week")
                Spacer()
            }
            .padding(.bottom, 4)

            Text("TODAY").font(.system(size: 8, weight: .medium, design: .monospaced)).foregroundStyle(Hekla.orange).kerning(1.5)

            ForEach(Array(today.enumerated()), id: \.offset) { _, entry in
                HStack(alignment: .top, spacing: 8) {
                    Text(entry.t).font(.system(size: 8, design: .monospaced)).foregroundStyle(Hekla.dim).frame(width: 34, alignment: .trailing)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(entry.action).font(.system(size: 10, weight: .medium)).foregroundStyle(Hekla.cream).lineLimit(1)
                            if entry.pending {
                                Text("PENDING").font(.system(size: 7, weight: .semibold, design: .monospaced)).foregroundStyle(Hekla.yellow).kerning(0.6)
                            }
                        }
                        Text(entry.detail).font(.system(size: 8)).foregroundStyle(Hekla.dim).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func countBadge(_ n: String, _ label: String) -> some View {
        HStack(spacing: 3) {
            Text(n).font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundStyle(Hekla.cream)
            Text(label).font(.system(size: 8, design: .monospaced)).foregroundStyle(Hekla.dim)
        }
    }
}

// MARK: - Generic fallback

struct GenericDetailContent: View {
    @Bindable var agent: AgentStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(agent.agent).font(.system(size: 14, weight: .semibold)).foregroundStyle(Hekla.cream)
            Text(agent.label).font(.system(size: 10)).foregroundStyle(Hekla.dim)
        }
    }
}
