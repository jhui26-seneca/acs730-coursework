locals {
  # Basic monitoring publishes EC2 metrics every 300 s, detailed every 60 s.
  # The alarm period must match, or the alarm never sees a datapoint.
  alarm_period = var.detailed_monitoring ? 60 : 300
}

# Task 7: an alarm on a real metric. CPUUtilization reports even on an idle
# instance, so the alarm leaves INSUFFICIENT_DATA once a few periods have passed.
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "${local.name_prefix}-cpu-alarm"
  alarm_description   = "ACS730 assign1 ${var.environment}: average CPU of ${local.name_prefix}-web above ${var.cpu_alarm_threshold}% for ${var.alarm_evaluation_periods} periods of ${local.alarm_period} s"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  dimensions          = { InstanceId = aws_instance.web.id }
  statistic           = "Average"
  period              = local.alarm_period
  evaluation_periods  = var.alarm_evaluation_periods
  threshold           = var.cpu_alarm_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "missing" # no data = INSUFFICIENT_DATA, never a fake OK

  tags = { Name = "${local.name_prefix}-cpu-alarm" }
}

# A health signal next to the load signal above. StatusCheckFailed is 1 when the instance (its operating
# system stops answering) or the host under it (hardware, power, network) fails AWS's checks. EC2
# publishes it every minute at no charge, with or without detailed monitoring, so the period is 60 s.
resource "aws_cloudwatch_metric_alarm" "status_check_failed" {
  alarm_name          = "${local.name_prefix}-status-alarm"
  alarm_description   = "ACS730 assign1 ${var.environment}: ${local.name_prefix}-web failed an EC2 status check (instance or host) for ${var.alarm_evaluation_periods} periods of 60 s"
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed"
  dimensions          = { InstanceId = aws_instance.web.id }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = var.alarm_evaluation_periods
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "missing" # no data = INSUFFICIENT_DATA, never a fake OK

  tags = { Name = "${local.name_prefix}-status-alarm" }
}
