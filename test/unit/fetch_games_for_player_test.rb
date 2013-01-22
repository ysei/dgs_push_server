require 'test_helper'
require 'mocha/setup'

class FetchGamesForPlayerTest < ActiveSupport::TestCase
  setup do
    players(:justin).session.update_attribute(:expires_at, 1.week.from_now)
  end

  test "When a player is queued, the game list is retrieved and notifications are sent" do
    mock_dgs_with_response(game_csv(1)) do
      assert_difference "Rapns::Apns::Notification.count", 1 do
        FetchGamesForPlayer.new.perform(players(:justin).id)
        assert 1.minute.ago < players(:justin).reload.last_checked_at, "last_checked_at should have been updated"
      end
    end
  end

  test "When a player is not found, the fetcher does nothing" do
    assert_difference "Rapns::Apns::Notification.count", 0 do
      # The request will fail if this actually tried to make it
      FetchGamesForPlayer.new.perform(1000)
    end
  end

  test "When a player isn't ready for checking, the fetcher does nothing" do
    players(:justin).update_attribute(:last_checked_at, Time.now)
    assert_difference "Rapns::Apns::Notification.count", 0 do
      # The request will fail if this actually tried to make it
      FetchGamesForPlayer.new.perform(players(:justin).id)
    end
  end

  test "A player without push tokens will not attempt to fetch" do
    assert_difference "Rapns::Apns::Notification.count", 0 do
      # The request will fail if this actually tried to make it
      FetchGamesForPlayer.new.perform(players(:player_without_tokens).id)
    end
  end

  test "A player whose session is about to expire should not fetch and should get a notification, and the session should get deleted" do
    players(:justin).session.update_attribute(:expires_at, 1.week.ago)
    assert_difference "Session.count", -1 do
      assert_difference "Rapns::Apns::Notification.count", 1 do
        # The request will fail if this actually tried to make it
        FetchGamesForPlayer.new.perform(players(:justin).id)
      end
    end
  end

  test "A player whose session fails should get a notification, and the session should get deleted" do
    assert_difference "Session.count", -1 do
      assert_difference "Rapns::Apns::Notification.count", 1 do
        DGS.any_instance.expects(:get).raises(DGS::NotLoggedInException)
        FetchGamesForPlayer.new.perform(players(:justin).id)
      end
    end
  end

  test "Even if we can't find a session, we should still update the last_checked_at" do
    players(:justin).session.update_attribute(:expires_at, 1.week.ago)
    assert_difference "Session.count", -1 do
      assert_difference "Rapns::Apns::Notification.count", 1 do
        # The request will fail if this actually tried to make it
        FetchGamesForPlayer.new.perform(players(:justin).id)
      end
    end
    assert 1.minute.ago < players(:justin).reload.last_checked_at, "last_checked_at should have been updated"
  end

  test "When we have no session, we should fail silently" do
    players(:justin).session.destroy
    assert_difference "Session.count", 0 do
      assert_difference "Rapns::Apns::Notification.count", 0 do
        # The request will fail if this actually tried to make it
        FetchGamesForPlayer.new.perform(players(:justin).id)
      end
    end
  end

  test "Data doesn't get updated on a random failure" do
    mock_dgs_with_response(game_csv(3)) do
      assert_difference "Game.count", 0 do
        assert_raises RuntimeError do
          Player.any_instance.expects(:create_notifications_for_games!).raises(RuntimeError)
          FetchGamesForPlayer.new.perform(players(:justin).id)
        end
      end
    end
  end
end
