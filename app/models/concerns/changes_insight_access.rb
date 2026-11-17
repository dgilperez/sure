# For records whose changes decide which accounts every member of a family can
# open: shares, account ownership, membership. When such a change commits, the
# family's insight totals come off the feed and are rebuilt (see
# Insight.expire_totals_after_access_change). Each model says which of its
# changes count, so unrelated saves cost nothing.
module ChangesInsightAccess
  extend ActiveSupport::Concern

  included do
    after_commit :expire_insight_totals, if: :insight_access_changed?
  end

  private
    def insight_access_changed?
      raise NotImplementedError
    end

    # Both families when the record moved: the one it left loses access too.
    def insight_access_family_ids
      destroyed? ? [ family_id ] : [ family_id_before_last_save, family_id ]
    end

    def expire_insight_totals
      insight_access_family_ids.compact.uniq.each do |family_id|
        Insight.expire_totals_after_access_change(family_id)
      end
    end
end
