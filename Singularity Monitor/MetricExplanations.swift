import SwiftUI
import LaTeXSwiftUI

private struct ExplanationScaffold<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var content: () -> Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.vertical, 16)
        }
        .background(Color.groupedBackground)
        .navigationTitle(title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }
}

private struct ExplanationParagraph: View {
    let text: LocalizedStringKey

    init(_ text: LocalizedStringKey) { self.text = text }

    var body: some View {
        Text(text)
            .font(.body)
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct ExplanationHeading: View {
    let text: LocalizedStringKey

    init(_ text: LocalizedStringKey) { self.text = text }

    var body: some View {
        Text(text)
            .font(.headline)
            .foregroundStyle(.primary)
    }
}

private struct ExplanationFormula: View {
    let latex: String

    init(_ latex: String) { self.latex = latex }

    var body: some View {
        LaTeX(latex)
            .font(.body)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 12)
            .padding(.horizontal)
            .background(Color.secondaryGroupedBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct StatisticsExplanation: View {
    let fitKind: FitKind

    var body: some View {
        let doublingForKind: String = {
            switch fitKind {
            case .exponential: return "$$T_{\\text{double}} = \\frac{\\ln 2}{b}$$"
            case .hyperexponential: return "$$T_{\\text{double}}(t) = \\frac{\\ln 2}{b + 2ct}$$"
            case .hyperbolic: return "$$T_{\\text{double}}(t) = \\frac{(t_s - t)\\,\\ln 2}{p}$$"
            case .sigmoid: return "$$T_{\\text{double}}(t) = \\frac{\\ln 2}{-b\\bigl(1 - \\sigma(a + bt)\\bigr)}$$"
            }
        }()
        let doublingIntuition: LocalizedStringKey = {
            switch fitKind {
            case .exponential: return "Exponential growth has a constant doubling time, so this number stays the same no matter when you look."
            case .hyperexponential: return "Hyperexponential growth speeds up over time, so the doubling time gets shorter as time goes on."
            case .hyperbolic: return "Near the singularity, the doubling time approaches zero — the curve doubles arbitrarily fast as it runs out of room."
            case .sigmoid: return "Sigmoid growth slows as it approaches its ceiling, so the doubling time grows without bound near the asymptote."
            }
        }()
        ExplanationScaffold(title: "Statistics") {
            ExplanationHeading("Doubling time")
            ExplanationParagraph("How long it takes the horizon length to double at the current rate. Smaller means faster progress.")
            ExplanationParagraph("Because the fit lives in log space, the doubling time falls out of its instantaneous slope:")
            ExplanationFormula("$$T_{\\text{double}} = \\frac{\\ln 2}{\\text{slope of }\\ln(\\text{minutes})\\text{ vs.\\ time}}$$")
            ExplanationParagraph("For the \(fitKind.longLabel) fit, that resolves to:")
            ExplanationFormula(doublingForKind)
            ExplanationParagraph(doublingIntuition)

            ExplanationHeading("Singularity")
            ExplanationParagraph("A stand-in date for when the curve predicts effectively unbounded capability. Specifically, it's when the projected horizon length first reaches 100 years — a practical proxy for \"out of human range.\"")
            switch fitKind {
            case .exponential:
                ExplanationParagraph("Exponential growth eventually reaches any threshold. The date here is when the constant-doubling line crosses 100 years.")
            case .hyperexponential:
                ExplanationParagraph("Hyperexponential growth accelerates, so it crosses 100 years sooner than a pure exponential would.")
            case .hyperbolic:
                ExplanationParagraph("Hyperbolic curves have a true vertical asymptote where the value blows up to infinity. The 100-year crossing sits a hair before that asymptote.")
                ExplanationFormula("$$\\ln(\\text{minutes}) = \\ln A - p\\,\\ln(t_s - t)$$")
            case .sigmoid:
                ExplanationParagraph("Sigmoid growth saturates at a ceiling L. If L stays below 100 years, the singularity is never — the curve plateaus before it gets there.")
            }
            ExplanationParagraph("Treat the date as a property of the chosen curve, not a literal forecast.")
        }
    }
}

struct RateOfChangeExplanation: View {
    var body: some View {
        ExplanationScaffold(title: "Rate of Change") {
            ExplanationParagraph("Each row shows how much the horizon length changes over that window, starting from right now.")

            ExplanationHeading("The percent")
            ExplanationFormula("$$\\frac{f(t + \\Delta t) - f(t)}{f(t)} \\times 100$$")
            ExplanationParagraph("It's the relative change between the curve's value now and its value one window from now.")

            ExplanationHeading("The duration")
            ExplanationFormula("$$\\Delta\\,\\text{minutes} = f(t + \\Delta t) - f(t)$$")
            ExplanationParagraph("It's the absolute change in horizon length over the same window, shown in whatever unit fits — milliseconds up through years.")

            ExplanationHeading("Why both")
            ExplanationParagraph("Percent shows pace. Duration shows scale. Together they make the rate readable whether the horizon is seconds or weeks long.")
        }
    }
}

struct FitExplanation: View {
    var body: some View {
        ExplanationScaffold(title: "Fit") {
            ExplanationParagraph("The fit is the curve you've chosen for the trend, the success rate it's measured against, and a quality score that tells you how well it matches the data.")

            ExplanationHeading("Curve")
            ExplanationParagraph("Each curve is a different guess about how horizon length grows over time. The app fits all four to the data and lets you compare them.")
            ExplanationFormula("$$\\textbf{Exponential:}\\ \\ln(\\text{minutes}) = a + bt$$")
            ExplanationParagraph("Constant doubling time. The straight-line story on a log chart.")
            ExplanationFormula("$$\\textbf{Hyperexponential:}\\ \\ln(\\text{minutes}) = a + bt + ct^2$$")
            ExplanationParagraph("Acceleration on top of exponential. Doubling time shrinks as time goes on.")
            ExplanationFormula("$$\\textbf{Hyperbolic:}\\ \\ln(\\text{minutes}) = \\ln A - p\\,\\ln(t_s - t)$$")
            ExplanationParagraph("Growth runs into a vertical asymptote at time t_s. Predicts a singularity.")
            ExplanationFormula("$$\\textbf{Sigmoid:}\\ \\text{minutes} = \\frac{L}{1 + e^{\\,a + bt}}$$")
            ExplanationParagraph("S-curve. Starts exponential, slows down, and saturates at a ceiling L.")

            ExplanationHeading("Metric")
            ExplanationParagraph("The success rate the horizon is measured against. 50% means the model finishes a task of that length half the time; 80% is the stricter, more reliable bar.")

            ExplanationHeading("R²")
            ExplanationParagraph("How closely the curve hugs the data, on a 0-to-1 scale.")
            ExplanationFormula("$$R^2 = 1 - \\frac{\\sum (y_i - \\hat{y}_i)^2}{\\sum (y_i - \\bar{y})^2}$$")
            ExplanationParagraph("Higher is better, but a high R² only describes the past. Use it to compare fits on the same data, not as proof the future will follow.")
        }
    }
}

struct ModelsExplanation: View {
    var body: some View {
        ExplanationScaffold(title: "Models") {
            ExplanationParagraph("This section lists every frontier model in METR's benchmark, newest first, with its measured horizon length on the selected metric.")

            ExplanationHeading("Next Up")
            ExplanationParagraph("A projection of when the next frontier release might land — and how capable it might be at that point.")
            ExplanationParagraph("The release date is extrapolated from the average gap between past releases:")
            ExplanationFormula("$$t_{\\text{next}} = t_{\\text{latest}} + \\frac{t_{\\text{latest}} - t_{\\text{earliest}}}{n - 1}$$")
            ExplanationParagraph("The horizon at that date is the selected curve evaluated at that future moment.")

            ExplanationHeading("The other models")
            ExplanationParagraph("Each row is a measured horizon from a real model run — Anthropic's Claude line, OpenAI's GPT/o-series, Google's Gemini, plus earlier baselines like davinci-002 and GPT-2. The number is how long a task the model finishes at the selected success rate.")

            ExplanationHeading("Why bother")
            ExplanationParagraph("The list is the raw evidence underneath the curve — the points the fit is drawn through. Tap \"Show previous models\" to see the longer history.")
        }
    }
}

struct HeroNowExplanation: View {
    var body: some View {
        ExplanationScaffold(title: "Current horizon") {
            ExplanationParagraph("The current horizon length predicted by the selected curve — how long a task a frontier model can complete with the chosen success rate.")

            ExplanationHeading("How it's calculated")
            ExplanationParagraph("It's the fitted curve evaluated at the current moment.")
            ExplanationFormula("$$\\text{minutes} = f(t_{\\text{now}})$$")

            ExplanationHeading("Why it ticks")
            ExplanationParagraph("Time keeps moving, and so does the curve. The number updates live so you can watch the trend in real time.")
        }
    }
}

struct HeroSingularityExplanation: View {
    var body: some View {
        ExplanationScaffold(title: "Until singularity") {
            ExplanationParagraph("A countdown to when the chosen curve first reaches a 100-year horizon — a practical stand-in for \"effectively unbounded capability.\"")

            ExplanationHeading("How it's calculated")
            ExplanationFormula("$$\\Delta t = t_{\\text{100y}} - t_{\\text{now}}$$")
            ExplanationParagraph("The 100-year crossing falls out of solving the selected curve for the threshold. For hyperbolic fits it's just before the vertical asymptote; for sigmoid fits it can be \"never\" if the curve plateaus below 100 years.")

            ExplanationHeading("A caveat")
            ExplanationParagraph("Treat the date as a property of the chosen curve, not a literal prediction about the world.")
        }
    }
}

struct HeroDoublingExplanation: View {
    var body: some View {
        ExplanationScaffold(title: "Doubling Time") {
            ExplanationParagraph("How long it takes the horizon length to double at the current rate. Smaller means faster progress.")

            ExplanationHeading("How it's calculated")
            ExplanationFormula("$$T_{\\text{double}} = \\frac{\\ln 2}{\\text{slope of }\\ln(\\text{minutes})\\text{ vs.\\ time}}$$")
            ExplanationParagraph("Each curve gives a different slope, so each implies a different doubling time. For exponential growth it's constant; for the others it changes with time.")
        }
    }
}
