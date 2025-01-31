
-- 2. What is the distribution of user activity levels (e.g., number of posts, likes, comments)
-- across the user base?

SELECT 
    u.id AS user_id,
    u.username,
    COALESCE(photo_count, 0) AS total_posts,
    COALESCE(comment_count, 0) AS total_comments,
    COALESCE(like_count, 0) AS total_likes
FROM 
    users u
LEFT JOIN 
    (SELECT user_id, COUNT(*) AS photo_count FROM photos GROUP BY user_id) p ON u.id = p.user_id
LEFT JOIN 
    (SELECT user_id, COUNT(*) AS comment_count FROM comments GROUP BY user_id) c ON u.id = c.user_id
LEFT JOIN 
    (SELECT user_id, COUNT(*) AS like_count FROM likes GROUP BY user_id) l ON u.id = l.user_id  
    LIMIT 20;    




-- 3. Calculate the average number of tags per post (photo_tags and photos tables).

select avg(tag_count) as avg_post_count from (
select p.id, count(pt.tag_id) as tag_count
from photos p 
left join 
photo_tags pt on p.id = pt.photo_id 
group by p.id
) x;

-- 4. Identify the top users with the highest engagement rates (likes, comments)
--  on their posts and rank them.

with CommentsCount as (
    select photo_id, count(*) as comment_count
    from comments
    group by photo_id
), 
LikesCount as (
    select photo_id, count(*) as likes_count 
    from likes  
    group by photo_id
),    
UserEngagement as (
    select p.user_id, 
    sum(c.comment_count + l.likes_count) as total_engagement,
    count(p.id) as post_count
    from photos p 
    left join 
    CommentsCount c on p.id = c.photo_id 
    left join 
    LikesCount l on p.id = l.photo_id
    group by p.user_id
)
select 
    u.id as user_id, u.username,
    ue.total_engagement, ue.post_count as total_post,
    case
        when ue.post_count > 0 then ue.total_engagement / ue.post_count
        else 0 
        end as engagement_rate
    from users u 
    left join 
    UserEngagement ue on u.id = ue.user_id 
order by engagement_rate desc
limit 10;  


-- 5. Which users have the highest number of followers and followings?


with follower_counts as ( select followee_id,count(follower_id) as followers_count 
               from follows 
               group by followee_id),
following_counts as  (select follower_id,count(followee_id) as followings_count 
		  from follows 
          group by follower_id)
 select  u.id, u.username,
 coalesce(fc.followers_count,0)as followers_count,
 coalesce(flc.followings_count,0) as followings_count
 from users u
 left join follower_counts fc on u.id=fc.followee_id
 left join following_counts flc on u.id=flc.follower_id 
 order by followers_count desc, followings_count desc;

-- 6. Calculate the average engagement rate (likes, comments) per post for each user.


SELECT 
u.id as user_id,u.username,
COALESCE(p.num_posts, 0) AS num_posts,
COALESCE(l.num_likes, 0) AS num_likes,
COALESCE(c.num_comments, 0) AS num_comments,
CASE WHEN COALESCE(p.num_posts, 0) = 0 THEN 0
     ELSE (COALESCE(l.num_likes, 0) + COALESCE(c.num_comments, 0)) / COALESCE(p.num_posts, 0)
     END AS avg_engagement_rate
FROM users u
LEFT JOIN (SELECT user_id, COUNT(*) AS num_posts 
           FROM photos
           GROUP BY user_id) p ON u.id = p.user_id
LEFT JOIN (SELECT user_id, COUNT(*) AS num_likes
		   FROM likes
           GROUP BY user_id) l ON u.id = l.user_id
LEFT JOIN (SELECT user_id, COUNT(*) AS num_comments 
           FROM comments 
           GROUP BY user_id) c ON u.id = c.user_id
ORDER BY avg_engagement_rate DESC
limit 10;
    
-- 7. Get the list of users who have never liked any post (users and likes tables)  

select  
    u.id as user_id,
    u.username
from 
    users u
left join 
    likes l on u.id = l.user_id
where 
    l.user_id is null;   
  

-- 10. Calculate the total number of likes, comments, and photo tags for each user.

with user_likes as (
   select
    p.user_id,
    count(l.photo_id) as total_likes 
    from photos p 
    left join
    likes l on p.id = l.user_id 
    group by p.user_id
),
user_comments as (
	  select
		p.user_id,
		count(c.photo_id) as total_comments
		from photos p 
		left join
		comments c on p.id = c.user_id 
		group by p.user_id      
), 
user_tags as (
     select 
	 p.user_id,
     count(pt.tag_id) as total_tags 
     from photos p 
     left join 
     photo_tags pt on p.id = pt.photo_id 
     group by p.user_id
)
select u.id as user_id, u.username, total_likes,
total_comments, total_tags
from users u 
left join 
user_likes ul on u.id = ul.user_id 
left join 
user_comments uc on u.id = uc.user_id 
left join
user_tags ut on u.id = ut.user_id 
order by total_likes desc, total_comments desc, total_tags desc
limit 20; 


-- 11. Rank users based on their total engagement (likes, comments, shares) over a month.

WITH MonthlyEngagement AS (
    SELECT u.id AS user_id, u.username, 
	COALESCE(l.total_likes, 0) AS total_likes, 
	COALESCE(c.total_comments, 0) AS total_comments,
	(COALESCE(l.total_likes, 0) + COALESCE(c.total_comments, 0)) AS total_engagement
    FROM users u
    LEFT JOIN (
        SELECT user_id, COUNT(photo_id) AS total_likes
        FROM likes
        WHERE DATE(created_at) >= '2024-07-01' OR DATE(created_at) <= '2024-07-31'
        GROUP BY user_id) l ON u.id = l.user_id
    LEFT JOIN (
        SELECT user_id, COUNT(id) AS total_comments
        FROM comments
        WHERE DATE(created_at) >= '2024-07-01' OR DATE(created_at) <= '2024-07-31'
        GROUP BY user_id) c ON u.id = c.user_id)
SELECT user_id, username, total_likes, total_comments, total_engagement, 
RANK() OVER (ORDER BY total_engagement DESC)
AS engagement_rank
FROM MonthlyEngagement
ORDER BY engagement_rank
limit 20;


-- 12. Retrieve the hashtags that have been used in posts with the highest average number of likes.
-- Use a CTE to calculate the average likes for each hashtag first.

WITH 
hashtag_avg_likes AS (
    SELECT 
        t.tag_name,
        COUNT(l.photo_id) AS total_likes,
        COUNT(l.photo_id) * 1.0 / COUNT(DISTINCT pt.photo_id) AS avg_likes_per_post
    FROM 
        tags t
    JOIN photo_tags pt ON t.id = pt.tag_id
    JOIN likes l ON pt.photo_id = l.photo_id
    GROUP BY t.tag_name
)
SELECT 
    tag_name,
    total_likes,
    avg_likes_per_post
FROM 
    hashtag_avg_likes
ORDER BY 
    avg_likes_per_post DESC
LIMIT 10;


-- 13. Retrieve the users who have started following someone after being followed by that person. 


 SELECT f1.follower_id, f1.followee_id
 FROM follows f1
 JOIN follows f2 ON f1.follower_id = f2.followee_id
 AND f1.followee_id = f2.follower_id
 WHERE f1.created_at > f2.created_at;
    
   


