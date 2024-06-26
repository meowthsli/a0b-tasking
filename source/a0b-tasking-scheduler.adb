--
--  Copyright (C) 2024, Vadim Godunko <vgodunko@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
--

pragma Restrictions (No_Elaboration_Code);

with System.Address_To_Access_Conversions;

with A0B.ARMv7M.CMSIS; use A0B.ARMv7M.CMSIS;

package body A0B.Tasking.Scheduler is

   package Runnable_Queue is

      use type System.Address;

      procedure Enqueue (TCB : not null Task_Control_Block_Access)
        with Pre => TCB.State = Runnable and TCB.Next = System.Null_Address;
      --  Enqueue given task to the end of the queue.

      procedure Dequeue (TCB : out Task_Control_Block_Access)
        with Post => TCB.Next = System.Null_Address;
      --  Dequeue first task in the queue.

   end Runnable_Queue;

   package Timer_Queue is

      use type System.Address;

      procedure Enqueue
        (TCB  : not null Task_Control_Block_Access;
         SO   : not null Timer_Suspension_Object_Access;
         Till : A0B.Types.Unsigned_64)
           with Pre =>
             SO.TCB = System.Null_Address and SO.Next = System.Null_Address;
      --  Enqueue given suspension object with appropriate order of time stamps.

      procedure Dequeue
        (TCB : out Task_Control_Block_Access;
         SO  : out Timer_Suspension_Object_Access;
         Now : A0B.Types.Unsigned_64);
      --  Dequeue first suspension object from the list when its time stamp
      --  was been passed.

   end Timer_Queue;

   -------------------
   -- Register_Task --
   -------------------

   procedure Run_Task (TCB : not null Task_Control_Block_Access) is
   begin
      Runnable_Queue.Enqueue (TCB);
   end Run_Task;

   --------------------
   -- Runnable_Queue --
   --------------------

   package body Runnable_Queue is

      package TCB_Conversion is
        new System.Address_To_Access_Conversions (Task_Control_Block);

      function To_Address
        (Item : Task_Control_Block_Access) return System.Address is
           (TCB_Conversion.To_Address (TCB_Conversion.Object_Pointer (Item)));

      function To_Pointer
        (Item : System.Address) return Task_Control_Block_Access is
           (Task_Control_Block_Access (TCB_Conversion.To_Pointer (Item)));

      Head : Task_Control_Block_Access;
      Tail : Task_Control_Block_Access;

      -------------
      -- Dequeue --
      -------------

      procedure Dequeue (TCB : out Task_Control_Block_Access) is
      begin
         if Head = null then
            TCB := null;

         else
            TCB  := Head;
            Head := To_Pointer (TCB.Next);
            Tail := (if Head /= null then Tail else null);

            TCB.Next := System.Null_Address;
         end if;
      end Dequeue;

      -------------
      -- Enqueue --
      -------------

      procedure Enqueue (TCB : not null Task_Control_Block_Access) is
      begin
         if Head = null then
            Head := TCB;
            Tail := TCB;

         else
            declare
               pragma Suppress (Access_Check);
            begin
               Tail.Next := To_Address (TCB);
               Tail      := TCB;
            end;
         end if;
      end Enqueue;

   end Runnable_Queue;

   --------------
   -- Set_True --
   --------------

   procedure Set_True (SO : aliased in out Suspension_Object) is
      use type System.Address;

      package TCB_Conversion is
        new System.Address_To_Access_Conversions (Task_Control_Block);

      function To_Pointer
        (Item : System.Address) return Task_Control_Block_Access is
           (Task_Control_Block_Access (TCB_Conversion.To_Pointer (Item)));

      TCB : Task_Control_Block_Access;

   begin
      SO.State := True;

      if SO.TCB /= System.Null_Address then
         TCB            := To_Pointer (SO.TCB);
         TCB.State      := Runnable;
         TCB.Suspension := System.Null_Address;

         SO.TCB   := System.Null_Address;
         SO.State := False;

         Runnable_Queue.Enqueue (TCB);
      end if;
   end Set_True;

   -------------------
   -- Suspend_Until --
   -------------------

   procedure Suspend_Until (Time_Stamp : A0B.Types.Unsigned_64) is
   begin
      Set_BASEPRI (SVCall_Priority);

      Current_Task.State := Blocked;

      Timer_Queue.Enqueue (Current_Task, Current_Task.Timer'Access, Time_Stamp);

      Set_BASEPRI (0);
   end Suspend_Until;

   -------------------
   -- Suspend_Until --
   -------------------

   procedure Suspend_Until (SO : aliased in out Suspension_Object) is
      package TCB_Conversion is
        new System.Address_To_Access_Conversions (Task_Control_Block);

      function To_Address
        (Item : Task_Control_Block_Access) return System.Address is
           (TCB_Conversion.To_Address (TCB_Conversion.Object_Pointer (Item)));

      --  function To_Pointer
      --    (Item : System.Address) return Task_Control_Block_Access is
      --       (Task_Control_Block_Access (TCB_Conversion.To_Pointer (Item)));

      package Suspension_Object_Conversions is
        new System.Address_To_Access_Conversions (Suspension_Object);

      function To_Address
        (Item : Suspension_Object_Access) return System.Address is
           (Suspension_Object_Conversions.To_Address
              (Suspension_Object_Conversions.Object_Pointer (Item)));

   begin
      Set_BASEPRI (SVCall_Priority);

      Current_Task.State := Blocked;

      SO.TCB := To_Address (Current_Task);

      Current_Task.Suspension := To_Address (SO'Unchecked_Access);
      --  SO.State := False;

      Set_BASEPRI (0);
   end Suspend_Until;

   -------------------------
   -- Switch_Current_Task --
   -------------------------

   procedure Switch_Current_Task is
      Item : Task_Control_Block_Access;

   begin
      if Current_Task.State = Runnable then
         --  Current task is runnable, put it back to the queue.

         Runnable_Queue.Enqueue (Current_Task);
      end if;

      Runnable_Queue.Dequeue (Item);

      Current_Task :=
        (if Item = null then Idle_Task_Control_Block'Access else Item);
   end Switch_Current_Task;

   -----------------------
   -- System_Timer_Tick --
   -----------------------

   procedure System_Timer_Tick (Time_Stamp : A0B.Types.Unsigned_64) is
      TCB  : Task_Control_Block_Access;
      Item : Timer_Suspension_Object_Access;

   begin
      loop
         Timer_Queue.Dequeue (TCB, Item, Time_Stamp);

         exit when TCB = null;

         TCB.State := Runnable;
         Runnable_Queue.Enqueue (TCB);
      end loop;
   end System_Timer_Tick;

   -----------------
   -- Timer_Queue --
   -----------------

   package body Timer_Queue is

      use type A0B.Types.Unsigned_64;

      package Suspension_Condition_Conversions is
        new System.Address_To_Access_Conversions (Timer_Suspension_Object);

      function To_Pointer
        (Item : System.Address) return Timer_Suspension_Object_Access is
           (Timer_Suspension_Object_Access
              (Suspension_Condition_Conversions.To_Pointer (Item)));

      function To_Address
        (Item : Timer_Suspension_Object_Access) return System.Address is
           (Suspension_Condition_Conversions.To_Address
              (Suspension_Condition_Conversions.Object_Pointer (Item)));

      package TCB_Conversion is
        new System.Address_To_Access_Conversions (Task_Control_Block);

      function To_Address
        (Item : Task_Control_Block_Access) return System.Address is
           (TCB_Conversion.To_Address (TCB_Conversion.Object_Pointer (Item)));

      function To_Pointer
        (Item : System.Address) return Task_Control_Block_Access is
           (Task_Control_Block_Access (TCB_Conversion.To_Pointer (Item)));

      Head : Timer_Suspension_Object_Access;

      -------------
      -- Dequeue --
      -------------

      procedure Dequeue
        (TCB : out Task_Control_Block_Access;
         SO  : out Timer_Suspension_Object_Access;
         Now : A0B.Types.Unsigned_64) is
      begin
         if Head = null
           or else Head.Till > Now
         then
            TCB := null;
            SO  := null;

         else
            SO      := Head;
            Head    := To_Pointer (SO.Next);
            SO.Next := System.Null_Address;

            TCB     := To_Pointer (SO.TCB);
            SO.TCB  := System.Null_Address;
         end if;
      end Dequeue;

      -------------
      -- Enqueue --
      -------------

      procedure Enqueue
        (TCB  : not null Task_Control_Block_Access;
         SO   : not null Timer_Suspension_Object_Access;
         Till : A0B.Types.Unsigned_64)
      is
         Previous : Timer_Suspension_Object_Access := null;
         Current  : Timer_Suspension_Object_Access := Head;

      begin
         SO.TCB  := To_Address (TCB);
         SO.Till := Till;

         loop
            exit when Current = null;
            exit when Current.Till > SO.Till;

            Previous := Current;
            Current  := To_Pointer (Current.Next);
         end loop;

         if Previous = null then
            SO.Next := To_Address (Head);
            Head    := SO;

         else
            SO.Next       := Previous.Next;
            Previous.Next := To_Address (SO);
         end if;
      end Enqueue;

   end Timer_Queue;

end A0B.Tasking.Scheduler;