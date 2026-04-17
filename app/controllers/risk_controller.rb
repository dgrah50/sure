class RiskController < ApplicationController
  def show
    @regime = RegimeDetector.new(Current.family).detect
    @risk_assessment = RiskAssessmentService.new(Current.family).assess
    @guardrails = @risk_assessment[:guardrails]
    @concentration = @risk_assessment[:concentration]
    @liquidity = @risk_assessment[:liquidity]
    @exposure = @risk_assessment[:exposure]
    @data_quality = @risk_assessment[:data_quality]
    @overall_risk_level = @risk_assessment[:overall_risk_level]
    
    @breadcrumbs = [ [ t(".nav.overview"), overview_path ], [ t(".title"), nil ] ]
  end

  private

  helper_method :regime_badge_color, :regime_icon, :regime_color, :guardrail_status_icon, :guardrail_status_color, :concentration_risk_color

  def regime_badge_color(mode)
    case mode
    when :crisis then :error
    when :caution then :warning
    when :normal then :success
    else :default
    end
  end

  def regime_icon(mode)
    case mode
    when :crisis then "alert-triangle"
    when :caution then "alert-circle"
    when :normal then "check-circle"
    else "help-circle"
    end
  end

  def regime_color(mode)
    case mode
    when :crisis then "destructive"
    when :caution then "warning"
    when :normal then "success"
    else "secondary"
    end
  end

  def guardrail_status_icon(status)
    case status
    when "pass" then "check-circle"
    when "violation" then "x-circle"
    else "help-circle"
    end
  end

  def guardrail_status_color(status)
    case status
    when "pass" then "text-success"
    when "violation" then "text-destructive"
    else "text-secondary"
    end
  end

  def concentration_risk_color(pct)
    if pct > 50
      "text-destructive"
    elsif pct > 25
      "text-warning"
    else
      "text-success"
    end
  end
end
