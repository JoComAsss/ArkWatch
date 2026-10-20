import SwiftUI
import AppKit

// MARK: - 套餐定义（价格与额度来自方舟官方文档「套餐概览」）

struct PlanTier: Identifiable {
    let id: String
    let family: String      // AgentPlan / CodingPlan
    let name: String
    let price: String
    let detail: String
    let video: Bool
}

enum PlanCatalog {
    static let consoleURL = URL(string: "https://ark.volcengine.com/region:cn-beijing/openManagement?LLM=%7B%7D&advancedActiveKey=agentPlan")!

    static let agentTiers: [PlanTier] = [
        PlanTier(id: "agent-small", family: "AgentPlan", name: "Small", price: "¥40 / 月",
                 detail: "月 20,000 · 周 7,000 · 5 小时 2,000 AFP", video: false),
        PlanTier(id: "agent-medium", family: "AgentPlan", name: "Medium", price: "¥200 / 月",
                 detail: "月 100,000 · 周 35,000 · 5 小时 10,000 AFP", video: false),
        PlanTier(id: "agent-large", family: "AgentPlan", name: "Large", price: "¥500 / 月",
                 detail: "月 250,000 · 周 87,500 · 5 小时 25,000 AFP", video: true),
        PlanTier(id: "agent-max", family: "AgentPlan", name: "Max", price: "¥1,000 / 月",
                 detail: "月 500,000 · 周 175,000 · 5 小时 50,000 AFP", video: true)
    ]

    static var allTiers: [PlanTier] { agentTiers + codingTiers }

    static func tier(id: String?) -> PlanTier? {
        guard let id else { return nil }
        return allTiers.first { $0.id == id }
    }

    static let codingTiers: [PlanTier] = [
        PlanTier(id: "coding-lite", family: "CodingPlan", name: "Lite", price: "以控制台为准",
                 detail: "按 5 小时 / 周窗口限流，额度见控制台", video: false),
        PlanTier(id: "coding-pro", family: "CodingPlan", name: "Pro", price: "以控制台为准",
                 detail: "按 5 小时 / 周窗口限流，额度见控制台", video: false)
    ]
}

// MARK: - 套餐面板

struct PlansView: View {
    @ObservedObject var model: AppModel
    var openConsole: () -> Void

    private var currentFamily: String {
        if let plan = model.plan { return plan.plan }
        return model.snapshot == nil ? "" : "AgentPlan"
    }

    private var currentType: String {
        model.plan?.planType ?? model.snapshot?.planType ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            section(title: "Agent Plan", subtitle: "面向 Agent 场景，含模型与 Harness 额度", tiers: PlanCatalog.agentTiers)
            section(title: "Coding Plan", subtitle: "面向编程工具，按 5 小时 / 周窗口限流", tiers: PlanCatalog.codingTiers)
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 500)
        .onAppear { model.detectPlan() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("全部套餐").font(.system(size: 14, weight: .semibold))
            if model.isCheckingPlan {
                chip("检测中", color: Color(red: 0.78, green: 0.60, blue: 0.05))
            } else if model.plan != nil {
                chip("已开通", color: .green)
            } else if model.activeAccount == nil {
                chip("未绑定账号", color: .secondary)
            } else {
                chip("未开通", color: .red)
            }
            Spacer()
        }
    }

    private func section(title: String, subtitle: String, tiers: [PlanTier]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 11, weight: .semibold))
                Text(subtitle).font(.system(size: 9)).foregroundStyle(.tertiary)
            }
            ForEach(tiers) { tier in
                row(tier)
            }
        }
    }

    private func row(_ tier: PlanTier) -> some View {
        let isLive = tier.id == model.livePlanID
        let isSelected = tier.id == (model.selectedPlanID ?? model.livePlanID)

        return HStack(spacing: 10) {
            // 红绿灯：绿色 = 已开通，灰色 = 未开通
            Circle()
                .fill(isLive ? Color.green : Color.red.opacity(0.85))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(tier.name).font(.system(size: 12, weight: .semibold))
                    if isLive { chip("已开通", color: .green) }
                    if !isLive { chip("未开通", color: .red) }
                    if isSelected && !isLive { chip("查看中", color: .accentColor) }
                    if tier.video { chip("含视频生成", color: .secondary) }
                }
                Text(tier.detail)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(tier.price)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)

            if !(isLive && isSelected) {
                Button("切换") {
                    model.selectedPlanID = tier.id
                }
                .controlSize(.small)
            }

            Button("开通") { openConsole() }
                .controlSize(.small)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(isSelected ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor.opacity(0.45) : Color.clear, lineWidth: 1)
        )
    }

    private func chip(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 8, weight: .medium))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .foregroundStyle(color)
            .background(color.opacity(0.14), in: Capsule())
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("点「开通」会在浏览器打开火山方舟控制台的开通管理页，可查看额度、购买或续费。")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("说明：接口只能读取已购买的那一档。「切换」仅切换本机查看对象，不会改变实际订阅；真正变更套餐请在控制台购买或升配。")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("打开控制台") { openConsole() }
                    .controlSize(.small)
            }
        }
    }
}
